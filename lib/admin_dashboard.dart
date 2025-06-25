// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:screenshot/screenshot.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'login.dart';

class AttendanceRecord {
  final String name;
  final String psName;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final String checkInLocation;
  final String? checkOutLocation;
  final String userId;
  AttendanceRecord({
    required this.name,
    required this.psName,
    required this.checkInTime,
    this.checkOutTime,
    required this.checkInLocation,
    this.checkOutLocation,
    required this.userId,
  });
  Duration get totalTimeCheckedIn => (checkOutTime ?? DateTime.now()).difference(checkInTime);
}

enum SortFilter { person, week, month, year, all }

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  SortFilter _selectedFilter = SortFilter.all;
  List<AttendanceRecord> allRecords = [];
  bool _isLoading = true;

  // FILTER STATE
  String? _selectedPsName;
  DateTime? _selectedDay;
  DateTimeRange? _selectedDateRange;
  int? _selectedMonth;
  int? _selectedYear;

  // Screenshot controllers for chart export
  final ScreenshotController _pieChartController = ScreenshotController();
  final ScreenshotController _barChartController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    setState(() {
      _isLoading = true;
      allRecords = [];
    });
    try {
      final users = await FirebaseFirestore.instance.collection('Users').get();
      List<AttendanceRecord> fetchedRecords = [];
      for (final user in users.docs) {
        final attendance = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user.id)
            .collection('attendance')
            .orderBy('checkInTime', descending: true)
            .get();
        final String psName = user.data()['psName'] as String? ?? 'Unknown PS';
        for (final recordDoc in attendance.docs) {
          final data = recordDoc.data();
          final AttendanceRecord record = AttendanceRecord(
            name: data['Name'] as String? ?? 'Unknown',
            psName: psName,
            checkInTime: (data['checkInTime'] as Timestamp).toDate(),
            checkOutTime: (data['checkOutTime'] as Timestamp?)?.toDate(),
            checkInLocation: data['checkInLocation'] as String? ?? 'N/A',
            checkOutLocation: data['checkOutLocation'] as String?,
            userId: user.id,
          );
          fetchedRecords.add(record);
        }
      }
      setState(() {
        allRecords = fetchedRecords;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load attendance data: $e')),
      );
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
        '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(hours)}h ${twoDigits(minutes)}m ${twoDigits(seconds)}s';
  }

  List<String> get _allPsNames {
    final set = <String>{};
    for (final record in allRecords) {
      set.add(record.psName);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  List<AttendanceRecord> get _filteredRecords {
    List<AttendanceRecord> records = List.from(allRecords);
    if (_selectedPsName != null) {
      records = records.where((r) => r.psName == _selectedPsName).toList();
    }
    if (_selectedDay != null) {
      records = records
          .where((r) =>
              r.checkInTime.year == _selectedDay!.year &&
              r.checkInTime.month == _selectedDay!.month &&
              r.checkInTime.day == _selectedDay!.day)
          .toList();
    } else if (_selectedDateRange != null) {
      records = records
          .where((r) =>
              !r.checkInTime.isBefore(_selectedDateRange!.start) &&
              !r.checkInTime.isAfter(_selectedDateRange!.end))
          .toList();
    } else if (_selectedMonth != null || _selectedYear != null) {
      records = records.where((r) {
        final matchMonth = _selectedMonth == null || r.checkInTime.month == _selectedMonth;
        final matchYear = _selectedYear == null || r.checkInTime.year == _selectedYear;
        return matchMonth && matchYear;
      }).toList();
    }
    final now = DateTime.now();
    switch (_selectedFilter) {
      case SortFilter.all:
        break;
      case SortFilter.person:
        records.sort((a, b) {
          int psComp = a.psName.compareTo(b.psName);
          if (psComp != 0) return psComp;
          return a.name.compareTo(b.name);
        });
        break;
      case SortFilter.week:
        records = records.where((record) {
          return record.checkInTime.isAfter(now.subtract(const Duration(days: 7)));
        }).toList();
        break;
      case SortFilter.month:
        records = records.where((record) {
          return record.checkInTime.year == now.year && record.checkInTime.month == now.month;
        }).toList();
        break;
      case SortFilter.year:
        records = records.where((record) {
          return record.checkInTime.year == now.year;
        }).toList();
        break;
    }
    return records;
  }

  // --- FILTERED ANALYTICS GETTERS ---
  int get _filteredCheckedInCount => _filteredRecords.where((r) => r.checkOutTime == null).length;

  int get _filteredTotalUniqueMarshals => _filteredRecords.map((r) => r.name).toSet().length;

  Map<String, Duration> get _filteredTotalHoursPerMarshal {
    final map = <String, Duration>{};
    for (final record in _filteredRecords) {
      map.update(
        record.name,
        (d) => d + record.totalTimeCheckedIn,
        ifAbsent: () => record.totalTimeCheckedIn,
      );
    }
    return map;
  }

  Map<String, String> get _filteredMarshalPsNames {
    final map = <String, String>{};
    for (final record in _filteredRecords) {
      map[record.name] = record.psName;
    }
    return map;
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: DropdownSearch<String>(
              items: (String? filter, _) async {
                if (filter == null || filter.isEmpty) return _allPsNames;
                return _allPsNames
                    .where((ps) => ps.toLowerCase().contains(filter.toLowerCase()))
                    .toList();
              },
              selectedItem: _selectedPsName,
              onChanged: (ps) => setState(() => _selectedPsName = ps),
              decoratorProps: const DropDownDecoratorProps(
                decoration: InputDecoration(
                  labelText: "Police Station",
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  border: OutlineInputBorder(),
                ),
              ),
              popupProps: const PopupProps.menu(
                fit: FlexFit.loose,
                searchFieldProps: TextFieldProps(
                  decoration: InputDecoration(
                    labelText: "Search Police Station",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              suffixProps: DropdownSuffixProps(
                clearButtonProps: const ClearButtonProps(isVisible: true),
                dropdownButtonProps: const DropdownButtonProps(isVisible: true),
              )),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('Day:'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDay ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _selectedDay = picked);
                },
                child: Text(_selectedDay == null
                    ? 'Select Day'
                    : '${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}'),
              ),
              if (_selectedDay != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _selectedDay = null),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('Date Range:'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _selectedDateRange,
                  );
                  if (picked != null) setState(() => _selectedDateRange = picked);
                },
                child: Text(_selectedDateRange == null
                    ? 'Select Range'
                    : '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}'
                        ' to '
                        '${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}'),
              ),
              if (_selectedDateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _selectedDateRange = null),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('Month:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _selectedMonth,
                hint: const Text('Select Month'),
                items: List.generate(12, (i) => i + 1)
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))))
                    .toList(),
                onChanged: (m) => setState(() => _selectedMonth = m),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _selectedYear,
                hint: const Text('Year'),
                items: [2025, 2026, 2027]
                    .map((y) => DropdownMenuItem(value: y, child: Text(y.toString())))
                    .toList(),
                onChanged: (y) => setState(() => _selectedYear = y),
              ),
              if (_selectedMonth != null || _selectedYear != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _selectedMonth = null;
                    _selectedYear = null;
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Builder(
            builder: (context) {
              String filterSummary = '';
              if (_selectedPsName != null) filterSummary += 'PS: $_selectedPsName  ';
              if (_selectedDay != null) {
                filterSummary +=
                    'Day: ${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}  ';
              }
              if (_selectedDateRange != null) {
                filterSummary +=
                    'Range: ${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}'
                    ' to ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}  ';
              }
              if (_selectedMonth != null) {
                filterSummary += 'Month: ${_selectedMonth.toString().padLeft(2, '0')}  ';
              }
              if (_selectedYear != null) filterSummary += 'Year: $_selectedYear  ';
              return filterSummary.isNotEmpty
                  ? Text('Active Filters: $filterSummary',
                      style: const TextStyle(fontWeight: FontWeight.bold))
                  : const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _getPieChartSections() {
    final int checkedIn = _filteredCheckedInCount;
    final int total = _filteredTotalUniqueMarshals;
    final double checkedInPercentage = total > 0 ? (checkedIn / total) * 100 : 0;
    final double checkedOutPercentage = total > 0 ? ((total - checkedIn) / total) * 100 : 0;
    return [
      PieChartSectionData(
        color: Colors.green,
        value: checkedInPercentage,
        title: '${checkedInPercentage.toStringAsFixed(1)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      PieChartSectionData(
        color: Colors.red,
        value: checkedOutPercentage,
        title: '${checkedOutPercentage.toStringAsFixed(1)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    ];
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(text),
      ],
    );
  }

  List<BarChartGroupData> _getBarGroups() {
    final List<String> marshalNames = _filteredTotalHoursPerMarshal.keys.toList();
    marshalNames.sort((a, b) {
      int psComp = (_filteredMarshalPsNames[a] ?? '').compareTo(_filteredMarshalPsNames[b] ?? '');
      if (psComp != 0) return psComp;
      return a.compareTo(b);
    });
    return marshalNames.asMap().entries.map((entry) {
      int index = entry.key;
      String name = entry.value;
      double totalHours = _filteredTotalHoursPerMarshal[name]?.inMinutes.toDouble() ?? 0;
      totalHours = totalHours / 60;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: double.parse(totalHours.toStringAsFixed(2)),
            color: Colors.blue,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
        showingTooltipIndicators: [0],
      );
    }).toList();
  }

  Widget _getBottomTitles(double value, TitleMeta meta) {
    final names = _filteredTotalHoursPerMarshal.keys.toList();
    names.sort((a, b) {
      int psComp = (_filteredMarshalPsNames[a] ?? '').compareTo(_filteredMarshalPsNames[b] ?? '');
      if (psComp != 0) return psComp;
      return a.compareTo(b);
    });
    String text = '';
    if (value.toInt() >= 0 && value.toInt() < names.length) {
      text = names[value.toInt()];
      final ps = _filteredMarshalPsNames[text] ?? '';
      text = '$text\n($ps)';
    }
    return SideTitleWidget(
      meta: meta,
      space: 10,
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _getLeftTitles(double value, TitleMeta meta) {
    if (value == meta.max || value == 0) return Container();
    return SideTitleWidget(
      meta: meta,
      space: 10,
      child: Text('${value.toStringAsFixed(2)}h', style: const TextStyle(fontSize: 10)),
    );
  }

  double _getMaxYValue() {
    if (_filteredTotalHoursPerMarshal.isEmpty) return 10;
    double maxHours = 0;
    for (final duration in _filteredTotalHoursPerMarshal.values) {
      double hours = duration.inMinutes / 60;
      if (hours > maxHours) maxHours = hours;
    }
    return (maxHours * 1.2).ceilToDouble();
  }

  // --- EXPORT TO EXCEL WITH CHART IMAGES ---
  Future<void> exportToExcelWithCharts(List<AttendanceRecord> records, BuildContext context) async {
    try {
      PermissionStatus status;
      if (Platform.isAndroid) {
        status = await Permission.manageExternalStorage.request();
      } else {
        status = PermissionStatus.granted;
      }
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission not granted. Cannot export.')),
        );
        return;
      }

      // Capture chart images
      final pieImage = await _pieChartController.capture();
      final barImage = await _barChartController.capture();

      // Create Excel workbook
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];

      // Add attendance data
      sheet.getRangeByName('A1').setText('Name');
      sheet.getRangeByName('B1').setText('PS Name');
      sheet.getRangeByName('C1').setText('Check-in Time');
      sheet.getRangeByName('D1').setText('Check-out Time');
      sheet.getRangeByName('E1').setText('Total Time');
      sheet.getRangeByName('F1').setText('Check-in Location');
      sheet.getRangeByName('G1').setText('Check-out Location');

      int row = 2;
      for (final record in records) {
        sheet.getRangeByName('A$row').setText(record.name);
        sheet.getRangeByName('B$row').setText(record.psName);
        sheet.getRangeByName('C$row').setText(_formatDateTime(record.checkInTime));
        sheet.getRangeByName('D$row').setText(record.checkOutTime != null
            ? _formatDateTime(record.checkOutTime!)
            : 'Still checked in');
        sheet.getRangeByName('E$row').setText(_formatDuration(record.totalTimeCheckedIn));
        sheet.getRangeByName('F$row').setText(record.checkInLocation);
        sheet.getRangeByName('G$row').setText(record.checkOutLocation ?? 'N/A');
        row++;
      }

      // Add Pie Chart Image
      if (pieImage != null) {
        final base64Pie = base64Encode(pieImage);
        sheet.pictures.addBase64(row + 2, 1, base64Pie);
      }

      // Add Bar Chart Image
      if (barImage != null) {
        final base64Bar = base64Encode(barImage);
        sheet.pictures.addBase64(row + 22, 1, base64Bar);
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      Directory? directory;
      String? savePath;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
        if (directory != null) {
          final List<String> paths = directory.path.split('/');
          String newPath = '';
          for (int x = 1; x < paths.length; x++) {
            String folder = paths[x];
            if (folder == 'Android') break;
            newPath += '/$folder';
          }
          newPath = '$newPath/Download';
          directory = Directory(newPath);
        }
        if (directory == null || !await directory.exists()) {
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      savePath = directory.path;

      final fileName = 'attendance_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File('$savePath/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel exported to $savePath/$fileName'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              final result = await OpenFilex.open(file.path);
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open file: ${result.message}')),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting Excel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Create User',
            onPressed: _showCreateUserDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAttendanceData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => exportToExcelWithCharts(_filteredRecords, context),
            tooltip: 'Export to Excel',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildFilters(),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Attendance Overview',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Marshals Checked In: $_filteredCheckedInCount'),
                                Text('Total Marshals: $_filteredTotalUniqueMarshals'),
                              ],
                            ),
                            const SizedBox(height: 15),
                            if (_filteredTotalUniqueMarshals > 0)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Check-in Status',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Screenshot(
                                    controller: _pieChartController,
                                    child: SizedBox(
                                      height: 200,
                                      child: PieChart(
                                        PieChartData(
                                          sections: _getPieChartSections(),
                                          centerSpaceRadius: 40,
                                          sectionsSpace: 2,
                                          borderData: FlBorderData(show: false),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildLegend(Colors.green, 'Checked In'),
                                      const SizedBox(width: 20),
                                      _buildLegend(Colors.red, 'Checked Out/Not In'),
                                    ],
                                  ),
                                  const SizedBox(height: 15),
                                ],
                              ),
                            const Text('Total Hours Logged:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            _filteredTotalHoursPerMarshal.isEmpty
                                ? const Text('No records yet to display chart.')
                                : Screenshot(
                                    controller: _barChartController,
                                    child: SizedBox(
                                      height: 250,
                                      child: BarChart(
                                        BarChartData(
                                          barGroups: _getBarGroups(),
                                          borderData: FlBorderData(
                                            show: true,
                                            border: Border.all(
                                                color: const Color(0xff37434d), width: 1),
                                          ),
                                          gridData: FlGridData(show: false),
                                          titlesData: FlTitlesData(
                                            show: true,
                                            bottomTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                getTitlesWidget: _getBottomTitles,
                                                reservedSize: 52,
                                              ),
                                            ),
                                            leftTitles: AxisTitles(
                                              sideTitles: SideTitles(
                                                showTitles: true,
                                                getTitlesWidget: _getLeftTitles,
                                                reservedSize: 52,
                                              ),
                                            ),
                                            topTitles: AxisTitles(
                                                sideTitles: SideTitles(showTitles: false)),
                                            rightTitles: AxisTitles(
                                                sideTitles: SideTitles(showTitles: false)),
                                          ),
                                          alignment: BarChartAlignment.spaceAround,
                                          maxY: _getMaxYValue(),
                                        ),
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: 15),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: DropdownButton<SortFilter>(
                      value: _selectedFilter,
                      onChanged: (SortFilter? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedFilter = newValue;
                          });
                        }
                      },
                      items: SortFilter.values.map((SortFilter filter) {
                        return DropdownMenuItem<SortFilter>(
                          value: filter,
                          child: Text(filter.toString().split('.').last),
                        );
                      }).toList(),
                    ),
                  ),
                  _filteredRecords.isEmpty
                      ? const Center(child: Text('No attendance records found for this filter.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredRecords.length,
                          itemBuilder: (context, index) {
                            final record = _filteredRecords[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Name: ${record.name}',
                                                style:
                                                    const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('PS Name: ${record.psName}',
                                                style:
                                                    const TextStyle(fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit_location_alt,
                                                  color: Colors.blue),
                                              onPressed: () => _showEditUserLocationDialog(
                                                  record.userId, record.name),
                                              tooltip: 'Edit Work Location',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete, color: Colors.red),
                                              onPressed: () =>
                                                  _deleteUser(record.userId, record.name),
                                              tooltip: 'Delete User',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Text('Check-in: ${_formatDateTime(record.checkInTime)}'),
                                    Text(
                                        'Check-out: ${record.checkOutTime != null ? _formatDateTime(record.checkOutTime!) : 'Still checked in'}'),
                                    Text(
                                        'Total Time: ${_formatDuration(record.totalTimeCheckedIn)}'),
                                    Text('Check-in Location: ${record.checkInLocation}'),
                                    Text('Check-out Location: ${record.checkOutLocation ?? 'N/A'}'),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  // --- DIALOGS AND OTHER METHODS ---

  void _showCreateUserDialog() {
    showDialog(
      context: context,
      builder: (context) => const CreateUserDialog(),
    ).then((_) {
      _fetchAttendanceData();
    }); //
  }

  Future<void> _showEditUserLocationDialog(String userId, String userName) async {
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection('Users').doc(userId).get();
    double? currentLat = (userDoc.data() as Map<String, dynamic>?)?['workLatitude'] as double?; //
    double? currentLon = (userDoc.data() as Map<String, dynamic>?)?['workLongitude'] as double?; //
    await showDialog(
      context: context,
      builder: (context) => EditUserLocationDialog(
        userId: userId,
        userName: userName,
        currentLatitude: currentLat,
        currentLongitude: currentLon,
      ),
    ).then((_) {
      _fetchAttendanceData();
    }); //
  }

  Future<void> _deleteUser(String userId, String userName) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete user "$userName"? '
              'This will remove all their attendance records and their user profile.'),
          actions: <Widget>[
            //
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red), //
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm) {
      //
      setState(() {
        _isLoading = true;
      });
      try {
        //
        final attendanceDocs = await FirebaseFirestore.instance
            .collection('Users')
            .doc(userId)
            .collection('attendance')
            .get();
        WriteBatch batch = FirebaseFirestore.instance.batch(); //
        for (var doc in attendanceDocs.docs) {
          batch.delete(doc.reference); //
        }
        await batch.commit();

        await FirebaseFirestore.instance.collection('Users').doc(userId).delete();
        ScaffoldMessenger.of(context).showSnackBar(
          //
          SnackBar(
            content: Text('User "$userName" and all their attendance data deleted successfully.'),
            duration: const Duration(seconds: 7),
          ),
        );
        _fetchAttendanceData(); //
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          //
          SnackBar(content: Text('Error deleting user "$userName": $e')),
        );
      } //
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) =>
                LoginPage()), // Replace LoginPage with your actual login page widget
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error logging out: $e')),
      );
    }
  }
}

// --- CreateUserDialog ---
class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key});

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState(); //
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(); //
  final _psNameController = TextEditingController();
  final _workLatitudeController = TextEditingController();
  final _workLongitudeController = TextEditingController();
  bool _isAdmin = false;
  bool _loading = false; //
  String? _error;

  Future<void> _createUser() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      //
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(), password: _passwordController.text.trim());
      double? workLat; //
      double? workLon;
      if (_workLatitudeController.text.isNotEmpty) {
        workLat = double.tryParse(_workLatitudeController.text.trim());
        if (workLat == null) {
          //
          setState(() {
            _error = 'Invalid Work Latitude. Please enter a number.';
            _loading = false;
          });
          return; //
        }
      }
      if (_workLongitudeController.text.isNotEmpty) {
        workLon = double.tryParse(_workLongitudeController.text.trim());
        if (workLon == null) {
          //
          setState(() {
            _error = 'Invalid Work Longitude. Please enter a number.';
            _loading = false;
          });
          return; //
        }
      }

      await FirebaseFirestore.instance.collection('Users').doc(cred.user!.uid).set({
        'Name': _nameController.text.trim(),
        'psName': _psNameController.text.trim(),
        'email': _emailController.text.trim(),
        'isAdmin': _isAdmin,
        'workLatitude': workLat,
        'workLongitude': workLon,
      });
      if (mounted) {
        //
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User created successfully!')));
        Navigator.pop(context); //
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message); //
    } catch (e) {
      setState(() => _error = e.toString()); //
    } finally {
      setState(() => _loading = false); //
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _psNameController.dispose();
    _workLatitudeController.dispose();
    _workLongitudeController.dispose();
    super.dispose(); //
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)), //
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v == null || v.isEmpty ? 'Enter name' : null,
              ),
              TextFormField(
                //
                controller: _psNameController,
                decoration: const InputDecoration(labelText: 'PS Name (Police Station)'),
                validator: (v) => v == null || v.isEmpty ? 'Enter police station name' : null,
              ),
              TextFormField(
                //
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v == null || !v.contains('@') ? 'Enter email' : null, //
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v == null || v.length < 6 ? 'Min 6 chars' : null, //
              ),
              TextFormField(
                controller: _workLatitudeController,
                decoration: const InputDecoration(labelText: 'Work Location Latitude (Optional)'),
                keyboardType: TextInputType.number, //
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return 'Please enter a valid number for latitude.';
                  }
                  return null; //
                },
              ),
              TextFormField(
                controller: _workLongitudeController,
                decoration: const InputDecoration(labelText: 'Work Location Longitude (Optional)'),
                keyboardType: TextInputType.number, //
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return 'Please enter a valid number for longitude.'; //
                  }
                  return null; //
                },
              ),
              CheckboxListTile(
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v!),
                title: const Text('Is Admin'),
                controlAffinity: ListTileControlAffinity.leading, //
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ), //
        ElevatedButton(
          onPressed: _loading
              ? null
              : () {
                  if (_formKey.currentState!.validate()) _createUser();
                },
          child: _loading
              ? const SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ), //
      ],
    );
  }
}

// --- EditUserLocationDialog ---
class EditUserLocationDialog extends StatefulWidget {
  final String userId;
  final String userName;
  final double? currentLatitude;
  final double? currentLongitude; //

  const EditUserLocationDialog({
    super.key,
    required this.userId,
    required this.userName,
    this.currentLatitude,
    this.currentLongitude,
  });
  @override
  State<EditUserLocationDialog> createState() => _EditUserLocationDialogState(); //
}

class _EditUserLocationDialogState extends State<EditUserLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _latitudeController; //
  late TextEditingController _longitudeController;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latitudeController = TextEditingController(text: widget.currentLatitude?.toString() ?? ''); //
    _longitudeController = TextEditingController(text: widget.currentLongitude?.toString() ?? '');
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose(); //
  }

  Future<void> _updateUserLocation() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      //
      _loading = true;
      _error = null;
    });
    try {
      //
      double? newLat = double.tryParse(_latitudeController.text.trim());
      double? newLon = double.tryParse(_longitudeController.text.trim());
      await FirebaseFirestore.instance.collection('Users').doc(widget.userId).update({
        //
        'workLatitude': _latitudeController.text.isEmpty ? null : newLat,
        'workLongitude': _longitudeController.text.isEmpty ? null : newLon,
      });
      if (mounted) {
        //
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Work location updated for ${widget.userName}')),
        );
        Navigator.pop(context); //
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to update location: $e';
      }); //
    } finally {
      setState(() {
        _loading = false;
      }); //
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Work Location for ${widget.userName}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)), //
              TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(labelText: 'Work Location Latitude'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    //
                    return 'Please enter a valid number.';
                  }
                  return null;
                }, //
              ),
              TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(labelText: 'Work Location Longitude'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  //
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return 'Please enter a valid number.'; //
                  }
                  return null; //
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ), //
        ElevatedButton(
          onPressed: _loading ? null : _updateUserLocation,
          child: _loading
              ? const SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ), //
      ],
    );
  }
}

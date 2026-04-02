import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SchedulePage(),
    );
  }
}

class TaskBlock {
  double top;
  double height;
  String name;
  bool isSelected;

  double _savedTop = 0;
  double _savedHeight = 60;
  double _dragTop = 0;

  late final TextEditingController controller;

  TaskBlock({
    required this.top,
    this.height = 60.0,
    this.name = '新任務',
    this.isSelected = false,
  }) {
    _savedTop = top;
    _savedHeight = height;
    _dragTop = top;
    controller = TextEditingController(text: name);
  }

  void saveSnapshot() {
    _savedTop = top;
    _savedHeight = height;
    _dragTop = top;
  }

  Map<String, dynamic> toJson() => {
        'top': top,
        'height': height,
        'name': name,
      };

  factory TaskBlock.fromJson(Map<String, dynamic> json) {
    return TaskBlock(
      top: (json['top'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      name: json['name'] as String,
    );
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const double hourHeight = 60.0;
  static const double snapUnit = 30.0;
  static const double canvasHeight = hourHeight * 24;

  final ScrollController _scrollController = ScrollController();
  final List<TaskBlock> _blocks = [];
  TaskBlock? _selectedBlock;
  bool _isAddingMode = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _pixelToTime(double y) {
    final totalMinutes = (y / hourHeight * 60).toInt();
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _timeRange(double top, double height) =>
      '${_pixelToTime(top)} - ${_pixelToTime(top + height)}';

  double _snap(double value) => (value / snapUnit).round() * snapUnit;

  bool _isColliding(double top, double height, {TaskBlock? exclude}) {
    for (final block in _blocks) {
      if (block == exclude) continue;
      final overlaps = top < block.top + block.height &&
                       top + height > block.top;
      if (overlaps) return true;
    }
    return false;
  }

  void _selectBlock(TaskBlock block) {
    for (final b in _blocks) b.isSelected = false;
    block.isSelected = true;
    _selectedBlock = block;
  }

  void _clearSelection() {
    for (final b in _blocks) b.isSelected = false;
    _selectedBlock = null;
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _blocks.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList('saved_schedule', jsonList);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('saved_schedule');
    if (jsonList == null) return;
    setState(() {
      _blocks
        ..clear()
        ..addAll(jsonList.map((s) => TaskBlock.fromJson(jsonDecode(s))));
    });
  }

  void _enterAddingMode() {
    setState(() {
      _isAddingMode = true;
      _clearSelection();
      FocusScope.of(context).unfocus();
    });
  }

  void _exitAddingMode() {
    setState(() => _isAddingMode = false);
  }

  void _tryAddBlock(double tapY) {
    final snappedTop = _snap(tapY).clamp(0.0, canvasHeight - snapUnit);
    const newHeight = snapUnit * 2;

    setState(() {
      if (_isColliding(snappedTop, newHeight)) return;
      final newBlock = TaskBlock(top: snappedTop, height: newHeight);
      _blocks.add(newBlock);
      _isAddingMode = false;
      _selectBlock(newBlock);
      _saveData();
    });
  }

  void _deleteSelectedBlock() {
    if (_selectedBlock == null) return;
    setState(() {
      _blocks.remove(_selectedBlock);
      _selectedBlock = null;
    });
    _saveData();
  }

  void _onDragStarted(TaskBlock block) {
    block.saveSnapshot();
  }

  void _onDragUpdate(TaskBlock block, DragUpdateDetails details) {
    setState(() {
      block._dragTop = (block._dragTop + details.delta.dy)
          .clamp(0.0, canvasHeight - block.height);
    });
  }

  void _onDragEnd(TaskBlock block) {
    setState(() {
      final snappedTop = _snap(block._dragTop);
      if (_isColliding(snappedTop, block.height, exclude: block)) {
        block.top = block._savedTop;
      } else {
        block.top = snappedTop;
        block._savedTop = block.top;
      }
      block._dragTop = block.top;
    });
    _saveData();
  }

  void _onResizeStart(TaskBlock block) {
    block.saveSnapshot();
  }

  void _onResizeUpdate(TaskBlock block, DragUpdateDetails details,
      {required bool isTopHandle}) {
    setState(() {
      if (isTopHandle) {
        final newTop = block.top + details.delta.dy;
        final newHeight = block.height - details.delta.dy;
        if (newTop >= 0 && newHeight >= snapUnit) {
          block.top = newTop;
          block.height = newHeight;
        }
      } else {
        final newHeight = block.height + details.delta.dy;
        if (block.top + newHeight <= canvasHeight && newHeight >= snapUnit) {
          block.height = newHeight;
        }
      }
    });
  }

  void _onResizeEnd(TaskBlock block) {
    setState(() {
      final snappedTop = _snap(block.top);
      final snappedHeight = _snap(block.height);
      if (_isColliding(snappedTop, snappedHeight, exclude: block)) {
        block.top = block._savedTop;
        block.height = block._savedHeight;
      } else {
        block.top = snappedTop;
        block.height = snappedHeight;
      }
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _buildFABs(),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (_isAddingMode) {
              final absoluteY =
                  details.localPosition.dy + _scrollController.offset;
              _tryAddBlock(absoluteY);
            } else {
              setState(() {
                _clearSelection();
                FocusScope.of(context).unfocus();
              });
            }
          },
          child: ColoredBox(
            color: _isAddingMode
                ? Colors.blue.withOpacity(0.05)
                : Colors.white,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                height: canvasHeight,
                child: Stack(
                  children: [
                    _buildHourGrid(),
                    ..._blocks.map(_buildDraggableBlock),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedBlock != null && !_isAddingMode) ...[
          FloatingActionButton(
            heroTag: 'delete',
            backgroundColor: Colors.red,
            onPressed: _deleteSelectedBlock,
            child: const Icon(Icons.delete),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton(
          heroTag: 'add',
          backgroundColor: _isAddingMode ? Colors.orange : Colors.blue,
          onPressed: _isAddingMode ? _exitAddingMode : _enterAddingMode,
          child: Icon(_isAddingMode ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  Widget _buildHourGrid() {
    return Column(
      children: List.generate(24, (hour) {
        return Container(
          height: hourHeight,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[100]!),
            ),
          ),
          alignment: Alignment.topLeft,
          child: Text(
            '  ${hour.toString().padLeft(2, '0')}:00',
            style: TextStyle(color: Colors.grey[300], fontSize: 12),
          ),
        );
      }),
    );
  }

  Widget _buildDraggableBlock(TaskBlock block) {
    return Positioned(
      top: block.top,
      left: 80,
      child: IgnorePointer(
        ignoring: _isAddingMode,
        child: LongPressDraggable<TaskBlock>(
          data: block,
          delay: const Duration(milliseconds: 150),
          maxSimultaneousDrags: block.isSelected ? 0 : 1,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.7,
              child: _buildBlockBody(block, isDragging: true),
            ),
          ),
          childWhenDragging: const SizedBox.shrink(),
          onDragStarted: () => _onDragStarted(block),
          onDragUpdate: (details) => _onDragUpdate(block, details),
          onDragEnd: (_) => _onDragEnd(block),
          child: GestureDetector(
            onTap: () => setState(() => _selectBlock(block)),
            child: _buildBlockBody(block),
          ),
        ),
      ),
    );
  }

  Widget _buildBlockBody(TaskBlock block, {bool isDragging = false}) {
    final isSelected = block.isSelected && !isDragging;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          size: Size(250, block.height),
          painter: BlockPainter(
            isSelected: isSelected,
            fillColor: Colors.blue[100]!.withOpacity(isDragging ? 0.5 : 0.8),
            borderColor: Colors.blue,
          ),
          child: SizedBox(width: 250, height: block.height),
        ),

        Positioned(
          top: 6,
          right: 10,
          child: IgnorePointer(
            child: Text(
              _timeRange(
                  isDragging ? block._dragTop : block.top, block.height),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),

        // ── 拉桿：往外移 -26px ──────────────────────────
        if (isSelected && !_isAddingMode) ...[
          Positioned(
            top: -17,
            left: 10,
            child: _buildResizeHandle(block, isTopHandle: true),
          ),
          Positioned(
            bottom: -17,
            right: 10,
            child: _buildResizeHandle(block, isTopHandle: false),
          ),
        ],

        Positioned.fill(
          child: Center(
            child: isSelected
                ? _buildNameTextField(block)
                : IgnorePointer(
                    child: Text(
                      block.name,
                      style: const TextStyle(
                        fontSize: 14,
                        decoration: TextDecoration.none,
                        color: Colors.black,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildResizeHandle(TaskBlock block, {required bool isTopHandle}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _onResizeStart(block),
      onPanUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: isTopHandle),
      onPanEnd: (_) => _onResizeEnd(block),
      child: Container(
        width: 60,
        height: 44,
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 40,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameTextField(TaskBlock block) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: TextField(
        controller: block.controller,
        textAlign: TextAlign.center,
        autofocus: true,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (value) => block.name = value,
        onSubmitted: (_) {
          setState(() => block.isSelected = false);
          _saveData();
        },
      ),
    );
  }
}

class BlockPainter extends CustomPainter {
  final bool isSelected;
  final Color fillColor;
  final Color borderColor;

  const BlockPainter({
    required this.isSelected,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double cornerRadius = 12;
    const double notchWidth = 60;
    const double notchHeight = 10;
    const double notchSlant = 8; // 保留參數但不再使用

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = _buildPath(
        size, cornerRadius, notchWidth, notchHeight, notchSlant);

    canvas.drawPath(path, fillPaint);
    if (isSelected) canvas.drawPath(path, borderPaint);
  }

Path _buildPath(
  Size size,
  double r,
  double notchW,
  double notchH,
  double slant,
) {
  final w = size.width;
  final h = size.height;

  notchH += 4;

  const double topL = 12.0;
  final double topR = topL + notchW;
  
  // Symmetry: Bottom notch starts from the right edge
  final double botR_Start = w - 12.0; 
  final double botL_End = botR_Start - notchW;
  
  const double nr =6.0; // Consistent corner radius

  final path = Path();

  // --- TOP EDGE (Left-aligned Notch) ---
  if (isSelected) {
    path.moveTo(0, notchH + nr);
    path.quadraticBezierTo(0, notchH, nr, notchH); // Curve In
    path.lineTo(topR - nr, notchH);                // Straight Line
    path.quadraticBezierTo(topR, notchH, topR, notchH - nr); // Curve Out
    path.lineTo(topR, nr);
    path.quadraticBezierTo(topR, 0, topR + nr, 0);
  } else {
    path.moveTo(r, 0);
  }

  // --- RIGHT SIDE ---
  path.lineTo(w - r, 0);
  path.quadraticBezierTo(w, 0, w, r);
  
  // If selected, stop the right wall early to start the bottom notch
  if (isSelected) {
    path.lineTo(w, h - notchH - nr); 
  } else {
    path.lineTo(w, h - r);
    path.quadraticBezierTo(w, h, w - r, h);
  }

  // --- BOTTOM EDGE (Right-aligned Notch, Symmetric to Top-Left) ---
  if (isSelected) {
    // 1. Curve IN from the right edge to the notch depth
    path.quadraticBezierTo(w, h - notchH, w - nr, h - notchH);
    
    // 2. Straight horizontal line (Symmetric to top)
    path.lineTo(botL_End + nr, h - notchH);
    
    // 3. Curve OUT and drop down to the true bottom
    path.quadraticBezierTo(botL_End, h - notchH, botL_End, h - notchH + nr);
    path.lineTo(botL_End, h - nr);
    path.quadraticBezierTo(botL_End, h, botL_End - nr, h);
    
    // 4. Finish the bottom edge to the left
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
  } else {
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
  }

  // --- LEFT SIDE ---
  path.lineTo(0, isSelected ? notchH + nr : r);

  if (!isSelected) {
    path.quadraticBezierTo(0, 0, r, 0);
  }

  path.close();
  return path;
}

  @override
  bool shouldRepaint(covariant BlockPainter old) =>
      old.isSelected != isSelected ||
      old.fillColor != fillColor ||
      old.borderColor != borderColor;
}

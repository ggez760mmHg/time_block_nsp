import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

/// Professional Custom Gesture Recognizer to beat the Scrollable parent.
class ResizeDragRecognizer extends VerticalDragGestureRecognizer {
  final VoidCallback onStart;
  final Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;

  ResizeDragRecognizer({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
  }

  @override
  void onStart(int pointer) {
    super.onStart(pointer);
    onStart();
  }

  @override
  void handleUpdate(DragUpdateDetails details) {
    super.handleUpdate(details);
    onUpdate(details);
  }

  @override
  void onEnd(int pointer) {
    super.onEnd(pointer);
    onEnd();
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
        final double currentBottom = block._savedTop + block._savedHeight;
        double newTop = block.top + details.delta.dy;
        if (newTop >= 0 && (currentBottom - newTop) >= snapUnit) {
          block.top = newTop;
          block.height = currentBottom - newTop;
        }
      } else {
        double newHeight = block.height + details.delta.dy;
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
              physics: const AlwaysScrollableScrollPhysics(),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            ignoring: _isAddingMode,
            child: LongPressDraggable<TaskBlock>(
              data: block,
              delay: const Duration(milliseconds: 150),
              maxSimultaneousDrags: block.isSelected ? 0 : 1,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.7,
                  child: _buildBlockBody(block, isDragging: true, showHandles: false),
                ),
              ),
              childWhenDragging: const SizedBox.shrink(),
              onDragStarted: () => _onDragStarted(block),
              onDragUpdate: (details) => _onDragUpdate(block, details),
              onDragEnd: (_) => _onDragEnd(block),
              child: GestureDetector(
                onTap: () => setState(() => _selectBlock(block)),
                child: _buildBlockBody(block, showHandles: false),
              ),
            ),
          ),
          if (block.isSelected && !_isAddingMode)
            Positioned.fill(
              child: _buildHandlesOverlay(block),
            ),
        ],
      ),
    );
  }

  Widget _buildHandlesOverlay(TaskBlock block) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -17,
          left: -2,
          child: ResizeHandle(
            isTopHandle: true,
            onStart: () => _onResizeStart(block),
            onUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: true),
            onEnd: () => _onResizeEnd(block),
          ),
        ),
        Positioned(
          bottom: -17,
          right: -2,
          child: ResizeHandle(
            isTopHandle: false,
            onStart: () => _onResizeStart(block),
            onUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: false),
            onEnd: () => _onResizeEnd(block),
          ),
        ),
      ],
    );
  }

  Widget _buildBlockBody(TaskBlock block, {bool isDragging = false, bool showHandles = true}) {
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
        if (showHandles && isSelected && !_isAddingMode) ...[
          Positioned(
            top: -17,
            left: -2,
            child: ResizeHandle(
              isTopHandle: true,
              onStart: () => _onResizeStart(block),
              onUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: true),
              onEnd: () => _onResizeEnd(block),
            ),
          ),
          Positioned(
            bottom: -17,
            right: -2,
            child: ResizeHandle(
              isTopHandle: false,
              onStart: () => _onResizeStart(block),
              onUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: false),
              onEnd: () => _onResizeEnd(block),
            ),
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

class ResizeHandle extends StatefulWidget {
  final bool isTopHandle;
  final VoidCallback onStart;
  final Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;

  const ResizeHandle({
    super.key,
    required this.isTopHandle,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  late ResizeDragRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = ResizeDragRecognizer(
      onStart: widget.onStart,
      onUpdate: widget.onUpdate,
      onEnd: widget.onEnd,
    );
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        ResizeDragRecognizer: _recognizer,
      },
      child: Container(
        width: 80,
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
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final RRect rrect = RRect.fromLTRBR(
      0, 0, size.width, size.height, 
      radius: const Radius.circular(cornerRadius)
    );

    canvas.drawRRect(rrect, fillPaint);
    if (isSelected) {
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BlockPainter oldDelegate) {
    return oldDelegate.isSelected != isSelected || 
           oldDelegate.fillColor != fillColor || 
           oldDelegate.borderColor != borderColor;
  }
}

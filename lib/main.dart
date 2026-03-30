import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

// ═══════════════════════════════════════════════════════════
//  App 入口
// ═══════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════
//  資料模型：TaskBlock
// ═══════════════════════════════════════════════════════════

class TaskBlock {
  // ── 持久化欄位 ──────────────────────────────────────────
  double top;      // 距頂端距離（像素），對應時間軸位置
  double height;   // 方塊高度（像素）
  String name;     // 任務名稱

  // ── 編輯狀態 ────────────────────────────────────────────
  bool isSelected;

  // ── 拖曳 / 縮放的暫存值 ──────────────────────────────────
  // 操作開始前先存舊值；若結果碰撞，則彈回這些值
  double _savedTop = 0;
  double _savedHeight = 60;

  // 拖曳進行中的即時位置（不直接改 top，避免污染碰撞判斷基準）
  double _dragTop = 0;

  // ── 文字輸入控制器 ───────────────────────────────────────
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

  // ── 快照目前狀態（操作開始時呼叫）──────────────────────────
  void saveSnapshot() {
    _savedTop = top;
    _savedHeight = height;
    _dragTop = top;
  }

  // ── 序列化 ───────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'top': top,
        'height': height,
        'name': name,
      };

  factory TaskBlock.fromJson(Map<String, dynamic> json) {
    final block = TaskBlock(
      top: (json['top'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      name: json['name'] as String,
    );
    return block;
  }
}

// ═══════════════════════════════════════════════════════════
//  主畫面
// ═══════════════════════════════════════════════════════════

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  // ── 常數 ─────────────────────────────────────────────────
  static const double hourHeight = 60.0;  // 每小時對應的像素高度
  static const double snapUnit = 30.0;    // 吸附單位（30 分鐘 = 30px）
  static const double canvasHeight = hourHeight * 24;

  // ── 狀態 ─────────────────────────────────────────────────
  final List<TaskBlock> _blocks = [];
  TaskBlock? _selectedBlock;
  bool _isAddingMode = false;

  // ═══════════════════════════════════════════════════════
  //  生命週期
  // ═══════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ═══════════════════════════════════════════════════════
  //  工具方法
  // ═══════════════════════════════════════════════════════

  /// 將像素位置轉成「HH:MM」時間字串
  String _pixelToTime(double y) {
    final totalMinutes = (y / hourHeight * 60).toInt();
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 回傳方塊的時間範圍字串，例如 "09:00 - 10:30"
  String _timeRange(double top, double height) =>
      '${_pixelToTime(top)} - ${_pixelToTime(top + height)}';

  /// 將數值對齊到最近的 snapUnit
  double _snap(double value) => (value / snapUnit).round() * snapUnit;

  /// 判斷給定位置與高度是否與其他方塊碰撞
  /// [exclude]：排除自身，避免自我碰撞誤判
  bool _isColliding(double top, double height, {TaskBlock? exclude}) {
    for (final block in _blocks) {
      if (block == exclude) continue;
      final overlaps = top < block.top + block.height &&
                       top + height > block.top;
      if (overlaps) return true;
    }
    return false;
  }

  /// 選取指定方塊，其餘取消選取
  void _selectBlock(TaskBlock block) {
    for (final b in _blocks) b.isSelected = false;
    block.isSelected = true;
    _selectedBlock = block;
  }

  /// 清除所有選取狀態
  void _clearSelection() {
    for (final b in _blocks) b.isSelected = false;
    _selectedBlock = null;
  }

  // ═══════════════════════════════════════════════════════
  //  資料持久化
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  //  操作：新增 / 刪除 / 模式切換
  // ═══════════════════════════════════════════════════════

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

  /// 使用者在新增模式下點擊畫布時呼叫
  void _tryAddBlock(double tapY) {
    final snappedTop = _snap(tapY).clamp(0.0, canvasHeight - snapUnit);
    const newHeight = snapUnit * 2; // 預設 1 小時

    if (_isColliding(snappedTop, newHeight)) return;

    setState(() {
      final newBlock = TaskBlock(top: snappedTop, height: newHeight);
      _blocks.add(newBlock);
      _isAddingMode = false;
      _selectBlock(newBlock);
    });
    _saveData();
  }

  void _deleteSelectedBlock() {
    if (_selectedBlock == null) return;
    setState(() {
      _blocks.remove(_selectedBlock);
      _selectedBlock = null;
    });
    _saveData();
  }

  // ═══════════════════════════════════════════════════════
  //  操作：拖曳移動
  // ═══════════════════════════════════════════════════════

  void _onDragStarted(TaskBlock block) {
    block.saveSnapshot(); // 記錄拖曳前位置，供碰撞彈回使用
  }

  void _onDragUpdate(TaskBlock block, DragUpdateDetails details) {
    setState(() {
      // 更新暫存拖曳位置，不直接改 block.top
      // 這樣 _isColliding 在判斷其他方塊時，仍以穩定的 block.top 為基準
      block._dragTop = (block._dragTop + details.delta.dy)
          .clamp(0.0, canvasHeight - block.height);
    });
  }

  void _onDragEnd(TaskBlock block) {
    setState(() {
      final snappedTop = _snap(block._dragTop);
      if (_isColliding(snappedTop, block.height, exclude: block)) {
        // 碰撞：彈回原位
        block.top = block._savedTop;
      } else {
        // 成功落點
        block.top = snappedTop;
        block._savedTop = block.top;
      }
      block._dragTop = block.top;
    });
    _saveData();
  }

  // ═══════════════════════════════════════════════════════
  //  操作：縮放（上下把手）
  // ═══════════════════════════════════════════════════════

  void _onResizeStart(TaskBlock block) {
    block.saveSnapshot();
  }

  void _onResizeUpdate(TaskBlock block, DragUpdateDetails details, {required bool isTopHandle}) {
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
        // 碰撞：彈回縮放前的大小
        block.top = block._savedTop;
        block.height = block._savedHeight;
      } else {
        block.top = snappedTop;
        block.height = snappedHeight;
      }
    });
    _saveData();
  }

  // ═══════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _buildFABs(),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (_isAddingMode) {
              _tryAddBlock(details.localPosition.dy);
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

  // ── FAB 群組 ─────────────────────────────────────────────

  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 刪除鈕（僅有選取方塊時顯示）
        if (_selectedBlock != null && !_isAddingMode) ...[
          FloatingActionButton(
            heroTag: 'delete',
            backgroundColor: Colors.red,
            onPressed: _deleteSelectedBlock,
            child: const Icon(Icons.delete),
          ),
          const SizedBox(height: 10),
        ],
        // 新增 / 取消 切換鈕
        FloatingActionButton(
          heroTag: 'add',
          backgroundColor: _isAddingMode ? Colors.orange : Colors.blue,
          onPressed: _isAddingMode ? _exitAddingMode : _enterAddingMode,
          child: Icon(_isAddingMode ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  // ── 時間格線 ─────────────────────────────────────────────

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

  // ── 可拖曳方塊 ────────────────────────────────────────────

  Widget _buildDraggableBlock(TaskBlock block) {
    return Positioned(
      top: block.top,
      left: 80,
      child: IgnorePointer(
        // 新增模式下整個方塊不接受點擊，避免誤觸
        ignoring: _isAddingMode,
        child: LongPressDraggable<TaskBlock>(
          data: block,
          delay: const Duration(milliseconds: 150),
          // 選取中時不允許拖曳（避免與縮放把手衝突）
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

  // ── 方塊外觀 ──────────────────────────────────────────────

  Widget _buildBlockBody(TaskBlock block, {bool isDragging = false}) {
    final isSelected = block.isSelected && !isDragging;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 主體
        CustomPaint(
          size: Size(250, block.height),
          painter: BlockPainter(
            isSelected: isSelected,
            fillColor: Colors.blue[100]!.withOpacity(isDragging ? 0.5 : 0.8),
            borderColor: Colors.blue,
          ),
          child: SizedBox(
            width: 250,
            height: block.height,
            child: Padding(
              padding: const EdgeInsets.only(top: 18, left: 15),
              child: Text(
                // 拖曳中顯示暫存位置，其餘顯示 block.top
                _timeRange(isDragging ? block._dragTop : block.top, block.height),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),

        // 縮放把手（僅選取時顯示）
        if (isSelected) ...[
          Positioned(
            top: -12, left: 0, right: 0,
            child: Center(child: _buildResizeHandle(block, isTopHandle: true)),
          ),
          Positioned(
            bottom: -12, left: 0, right: 0,
            child: Center(child: _buildResizeHandle(block, isTopHandle: false)),
          ),
        ],

        // 任務名稱（選取時為輸入框，否則為純文字）
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

  // ── 縮放把手 ──────────────────────────────────────────────

  Widget _buildResizeHandle(TaskBlock block, {required bool isTopHandle}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _onResizeStart(block),
      onPanUpdate: (d) => _onResizeUpdate(block, d, isTopHandle: isTopHandle),
      onPanEnd: (_) => _onResizeEnd(block),
      child: Container(
        width: 320,
        height: 100,
        color: Colors.transparent,
        child: Align(
          alignment: isTopHandle
              ? const Alignment(0, -0.8)
              : const Alignment(0, 0.8),
          child: Container(
            width: 45,
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

  // ── 名稱輸入框 ────────────────────────────────────────────

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

// ═══════════════════════════════════════════════════════════
//  方塊外形繪製器
// ═══════════════════════════════════════════════════════════

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
    const double notchSlant = 8;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = _buildPath(size, cornerRadius, notchWidth, notchHeight, notchSlant);

    canvas.drawPath(path, fillPaint);
    if (isSelected) canvas.drawPath(path, borderPaint);
  }

  /// 建立方塊路徑；選取時上下邊中間會出現缺口（讓縮放把手視覺更清楚）
  Path _buildPath(
    Size size,
    double r,
    double notchW,
    double notchH,
    double slant,
  ) {
    final w = size.width;
    final h = size.height;
    final notchLeft = (w - notchW) / 2;
    final notchRight = (w + notchW) / 2;

    final path = Path()..moveTo(r, 0);

    // 上邊（選取時有缺口）
    if (isSelected) {
      path
        ..lineTo(notchLeft - slant, 0)
        ..lineTo(notchLeft, notchH)
        ..lineTo(notchRight, notchH)
        ..lineTo(notchRight + slant, 0);
    }
    path
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      // 右邊
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h);

    // 下邊（選取時有缺口）
    if (isSelected) {
      path
        ..lineTo(notchRight + slant, h)
        ..lineTo(notchRight, h - notchH)
        ..lineTo(notchLeft, h - notchH)
        ..lineTo(notchLeft - slant, h);
    }
    path
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      // 左邊
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();

    return path;
  }

  @override
  bool shouldRepaint(covariant BlockPainter old) =>
      old.isSelected != isSelected ||
      old.fillColor != fillColor ||
      old.borderColor != borderColor;
}
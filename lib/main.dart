import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const TimeEditorCanvas(),
    );
  }
}

class TimeEditorCanvas extends StatefulWidget {
  const TimeEditorCanvas({super.key});
  @override
  State<TimeEditorCanvas> createState() => _TimeEditorCanvasState();
}

class _TimeEditorCanvasState extends State<TimeEditorCanvas> {
  // 原型參數：嚴格遵守
  double top = 120.0;
  double height = 150.0;
  bool isSelected = false;
  String taskName = "新任務";
  final TextEditingController _controller = TextEditingController();

  final double gridHourHeight = 60.0;
  final double snapUnit = 30.0;
  final int startHour = 9;
  final double maxCanvasHeight = 60.0 * 24; // 24小時限制範圍

  @override
  void initState() {
    super.initState();
    _controller.text = taskName;
  }

  String getTimeRange() {
    double startInMinutes = (top / gridHourHeight) * 60;
    double endInMinutes = ((top + height) / gridHourHeight) * 60;
    String formatTime(double totalMinutes) {
      int h = (totalMinutes / 60).floor() + startHour;
      int m = (totalMinutes % 60).round();
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
    }
    return "${formatTime(startInMinutes)} - ${formatTime(endInMinutes)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('具象化編輯器：原型鎖定版')),
      body: GestureDetector(
        onTap: () {
          setState(() {
            isSelected = false;
            FocusScope.of(context).unfocus();
          });
        },
        child: Container(
          color: Colors.white,
          child: Stack(
            children: [
              // 背景時間線
              ListView.builder(
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) => Container(
                  height: gridHourHeight,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
                  child: Text('  ${index + startHour}:00', style: TextStyle(color: Colors.grey[400])),
                ),
              ),

              // 積木
              Positioned(
                top: top,
                left: 80,
                child: LongPressDraggable<double>(
                  delay: const Duration(milliseconds: 150),
                  // Bug 修正 2：選取期間我不想要積木可以長按移動
                  maxSimultaneousDrags: isSelected ? 0 : 1,
                  feedback: Material(color: Colors.transparent, child: _buildBlock(isDragging: true)),
                  childWhenDragging: Container(),
                  onDragUpdate: (details) {
                    setState(() {
                      // Bug 修正 1：積木無法固定在時間內 (邊界限制)
                      double newTop = top + details.delta.dy;
                      top = newTop.clamp(0.0, maxCanvasHeight - height);
                    });
                  },
                  onDragEnd: (details) => setState(() {
                    top = (top / snapUnit).round() * snapUnit;
                  }),
                  child: _buildBlock(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 積木 UI 原型：永遠不改
  Widget _buildBlock({bool isDragging = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => setState(() => isSelected = !isSelected),
          child: CustomPaint(
            size: Size(250, height),
            painter: BlockPainter(
              isSelected: isSelected && !isDragging,
              color: Colors.blue[100]!.withOpacity(isDragging ? 0.5 : 0.8),
              borderColor: Colors.blue,
            ),
            child: SizedBox(
              width: 250,
              height: height,
              child: Stack(
                children: [
                  Positioned(
                    top: 18, left: 15,
                    child: Text(getTimeRange(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, decoration: TextDecoration.none)),
                  ),
                  Center(
                    child: isSelected && !isDragging
                        ? _buildCompactTextField()
                        : Text(taskName, style: const TextStyle(fontSize: 14, decoration: TextDecoration.none, color: Colors.black)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 懸浮藍色橢圓拉桿：永遠不改
        if (isSelected && !isDragging) ...[
          Positioned(
            top: -12,
            left: 0, right: 0,
            child: Center(child: _resizeHandle(isTop: true)),
          ),
          Positioned(
            bottom: -12,
            left: 0, right: 0,
            child: Center(child: _resizeHandle(isTop: false)),
          ),
        ],
      ],
    );
  }

  Widget _resizeHandle({required bool isTop}) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          double dy = details.delta.dy;
          if (isTop) {
            double newTop = top + dy;
            double newHeight = height - dy;
            // 縮放時同樣加入邊界防護
            if (newTop >= 0 && newHeight >= snapUnit) {
              top = newTop;
              height = newHeight;
            }
          } else {
            double newHeight = height + dy;
            if (top + newHeight <= maxCanvasHeight && newHeight >= snapUnit) {
              height = newHeight;
            }
          }
        });
      },
      onPanEnd: (_) => setState(() {
        height = (height / snapUnit).round() * snapUnit;
        top = (top / snapUnit).round() * snapUnit;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: Colors.transparent,
        child: Container(
          width: 45,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))
            ],
          ),
        ),
      ),
    );
  }

  // 文字框原型：永遠不改
  Widget _buildCompactTextField() {
    return GestureDetector(onTap: () {}, child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          autofocus: true,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          onChanged: (val) => taskName = val,
          onSubmitted: (val) => setState(() => isSelected = false),
        ),
    ));
  }
}

// 繪製路徑：永遠不改
class BlockPainter extends CustomPainter {
  final bool isSelected;
  final Color color;
  final Color borderColor;

  BlockPainter({required this.isSelected, required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 3;

    double notchW = 60;
    double notchH = 10;
    double slant = 8;  
    double radius = 12;

    Path path = Path();
    path.moveTo(radius, 0);

    if (isSelected) {
      path.lineTo((size.width - notchW) / 2 - slant, 0);
      path.lineTo((size.width - notchW) / 2, notchH);
      path.lineTo((size.width + notchW) / 2, notchH);
      path.lineTo((size.width + notchW) / 2 + slant, 0);
    }

    path.lineTo(size.width - radius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, radius);
    path.lineTo(size.width, size.height - radius);
    path.quadraticBezierTo(size.width, size.height, size.width - radius, size.height);

    if (isSelected) {
      path.lineTo((size.width + notchW) / 2 + slant, size.height);
      path.lineTo((size.width + notchW) / 2, size.height - notchH);
      path.lineTo((size.width - notchW) / 2, size.height - notchH);
      path.lineTo((size.width - notchW) / 2 - slant, size.height);
    }

    path.lineTo(radius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);
    path.lineTo(0, radius);
    path.quadraticBezierTo(0, 0, radius, 0);
    path.close();

    canvas.drawPath(path, paint);
    if (isSelected) canvas.drawPath(path, borderPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
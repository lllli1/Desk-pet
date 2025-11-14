import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(100, 100),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const DeskPetApp());
}

class DeskPetApp extends StatelessWidget {
  const DeskPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DeskPetHome(),
    );
  }
}

// 帧动画状态
enum PetState { idle, walk, drag }

// 帧动画控制器
class FrameAnimationController {
  PetState currentState = PetState.idle;
  int currentFrame = 0;
  Duration lastFrameTime = Duration.zero;
  final Duration frameDuration = const Duration(milliseconds: 100);

  int getFrameCount(PetState state) {
    switch (state) {
      case PetState.idle:
        return 12;
      case PetState.walk:
        return 11;
      case PetState.drag:
        return 35;
    }
  }

  bool updateFrame(Duration elapsed) {
    if (elapsed - lastFrameTime >= frameDuration) {
      lastFrameTime = elapsed;
      currentFrame = (currentFrame + 1) % getFrameCount(currentState);
      return true;
    }
    return false;
  }

  void setState(PetState newState) {
    if (currentState != newState) {
      final old = currentState;
      currentState = newState;
      currentFrame = 0;
      lastFrameTime = Duration.zero;
      debugPrint("🎬 动画状态切换: ${old.name} → ${newState.name}");
    }
  }

  String getCurrentFramePath() {
    final stateName = currentState.name;
    final frameNumber = (currentFrame + 1).toString().padLeft(3, '0');
    return 'assets/images/$stateName/${stateName}_$frameNumber.png';
  }
}

class DeskPetHome extends StatefulWidget {
  const DeskPetHome({super.key});

  @override
  State<DeskPetHome> createState() => _DeskPetHomeState();
}

class _DeskPetHomeState extends State<DeskPetHome>
    with SingleTickerProviderStateMixin, WindowListener {
  double x = 100, y = 100;
  bool isDragging = false;
  late Size screenSize;
  final double petSize = 100;

  late Ticker ticker;
  bool isMoving = false;
  double maxOffset = 200;
  double? targetX, targetY;
  final Random random = Random();
  Duration _lastMoveTime = Duration.zero;
  Duration _randomMoveInterval = const Duration(seconds: 3);
  Duration _currentElapsed = Duration.zero;

  final FrameAnimationController animationController =
      FrameAnimationController();

  final Map<String, ImageProvider> _imageCache = {};
  bool _imagesLoaded = false;
  bool _didPrecacheOnce = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this); // 🔥 关键：监听窗口事件
    debugPrint("🔧 DeskPetHome 初始化开始");
    _initializePetPosition();
    _setNewRandomMoveInterval();
  }

  // 🔥 窗口开始移动事件
  @override
  void onWindowMoved() {
    if (!isDragging) {
      debugPrint("🖱️ 系统开始拖拽窗口");
      setState(() {
        isDragging = true;
        isMoving = false;
        targetX = null;
        targetY = null;
        animationController.setState(PetState.drag);
      });
    }
  }

  // 🔥 窗口移动结束事件
  @override
  void onWindowEvent(String eventName) {
    // 当窗口事件流停止时，判断拖拽结束
    if (eventName == 'blur' || eventName == 'focus') {
      // 这些事件通常在拖拽结束后触发
      return;
    }
    debugPrint("📡 窗口事件: $eventName");
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didPrecacheOnce) {
      _didPrecacheOnce = true;
      _preloadImages();
    }
  }

  Future<void> _preloadImages() async {
    debugPrint("🚀 开始预加载图片...");
    final List<Map<String, dynamic>> states = [
      {'name': 'idle', 'count': 12},
      {'name': 'walk', 'count': 11},
      {'name': 'drag', 'count': 35},
    ];

    int successCount = 0;
    int failCount = 0;

    try {
      for (final state in states) {
        final String stateName = state['name'] as String;
        final int frameCount = state['count'] as int;
        debugPrint("📂 正在加载 $stateName 状态,共 $frameCount 帧");

        for (int i = 1; i <= frameCount; i++) {
          final frameNumber = i.toString().padLeft(3, '0');
          final path = 'assets/images/$stateName/${stateName}_$frameNumber.png';

          try {
            final imageProvider = AssetImage(path);
            _imageCache[path] = imageProvider;
            await precacheImage(imageProvider, context);
            successCount++;
            if (i % 10 == 0 || i == frameCount) {
              debugPrint("  ✅ $stateName: $i/$frameCount 帧已加载");
            }
          } catch (e) {
            failCount++;
            debugPrint("  ❌ 失败: $path");
          }
        }
      }

      debugPrint("📊 图片加载统计: 成功 $successCount 张, 失败 $failCount 张");

      if (mounted) {
        setState(() => _imagesLoaded = true);
        debugPrint("🎉 图片加载完成,启动物理循环");
        startPhysicsLoop();
      }
    } catch (e) {
      debugPrint("❌ 图片预加载过程异常: $e");
      if (mounted) {
        setState(() => _imagesLoaded = true);
        startPhysicsLoop();
      }
    }
  }

  Future<void> _initializePetPosition() async {
    debugPrint("📍 初始化桌宠位置...");
    final display = await screenRetriever.getPrimaryDisplay();
    if (!mounted) return;
    screenSize = display.size;
    setState(() {
      x = screenSize.width / 2 - petSize / 2;
      y = screenSize.height / 2 - petSize / 2;
    });
    await windowManager.setPosition(Offset(x, y));
    debugPrint("📍 桌宠位置: ($x, $y)");
  }

  void _setNewRandomMoveInterval() {
    _randomMoveInterval = Duration(seconds: random.nextInt(3) + 3);
    debugPrint("⏱️ 下次随机移动间隔: ${_randomMoveInterval.inSeconds}秒");
  }

  void startPhysicsLoop() {
    debugPrint("🎮 物理循环启动");
    ticker = createTicker((elapsed) {
      _currentElapsed = elapsed;
      if (!mounted) return;

      // 始终更新动画帧
      bool needsRepaint = animationController.updateFrame(elapsed);

      // 只在非拖拽、非移动状态下触发随机移动
      if (!isMoving && targetX == null && !isDragging) {
        if (elapsed - _lastMoveTime > _randomMoveInterval) {
          movePetRandomly();
          _lastMoveTime = elapsed;
          _setNewRandomMoveInterval();
        }
      }

      // 自动移动逻辑
      bool moved = false;
      if (!isDragging && targetX != null && targetY != null) {
        final dx = targetX! - x;
        final dy = targetY! - y;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance < 1.0) {
          setState(() {
            isMoving = false;
            targetX = null;
            targetY = null;
            animationController.setState(PetState.idle);
          });
          debugPrint("🎯 到达目标位置");
        } else {
          x += dx * 0.08;
          y += dy * 0.08;
          moved = true;
        }
      }

      if (moved && !isDragging) {
        x = x.clamp(0, screenSize.width - petSize);
        y = y.clamp(0, screenSize.height - petSize);
        windowManager.setPosition(Offset(x, y));
      }

      // 刷新UI
      if (needsRepaint || moved || isDragging) {
        if (mounted) setState(() {});
      }
    });
    ticker.start();
  }

  void movePetRandomly() {
    setState(() {
      isMoving = true;
      animationController.setState(PetState.walk);
      targetX = (x + (random.nextDouble() - 0.5) * 2 * maxOffset)
          .clamp(0, screenSize.width - petSize);
      targetY = (y + (random.nextDouble() - 0.5) * 2 * maxOffset)
          .clamp(0, screenSize.height - petSize);
    });
    debugPrint("🚶 桌宠开始移动: 目标 ($targetX, $targetY)");
  }

  void onTapPet() {
    debugPrint("👆 点击桌宠");
  }

  void onDragStart(DragStartDetails details) async {
    debugPrint("🖱️ 开始拖拽");
    _lastMoveTime = _currentElapsed;

    setState(() {
      isDragging = true;
      isMoving = false;
      targetX = null;
      targetY = null;
      animationController.setState(PetState.drag);
    });

    // 🔥 使用系统原生拖拽
    await windowManager.startDragging();

    // 🔥 拖拽结束后才会执行到这里
    debugPrint("🖱️ 拖拽真正结束");
    if (mounted) {
      setState(() {
        isDragging = false;
        animationController.setState(PetState.idle);
      });
      _lastMoveTime = _currentElapsed;
    }
  }

  Widget buildPet() {
    if (!_imagesLoaded) {
      return Container(
        width: petSize,
        height: petSize,
        decoration: BoxDecoration(
          color: Colors.pinkAccent.withAlpha(230),
          borderRadius: BorderRadius.circular(petSize / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(64),
              blurRadius: 12,
              offset: const Offset(3, 4),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
        ),
      );
    }

    final currentPath = animationController.getCurrentFramePath();
    final cachedImage = _imageCache[currentPath];

    return GestureDetector(
      onTapDown: (_) => onTapPet(),
      onPanStart: onDragStart,
      child: Container(
        width: petSize,
        height: petSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(petSize / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(64),
              blurRadius: 12,
              offset: const Offset(3, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(petSize / 2),
          child: cachedImage != null
              ? Image(
                  image: cachedImage,
                  width: petSize,
                  height: petSize,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              : Container(
                  color: isDragging
                      ? Colors.orangeAccent.withAlpha(230)
                      : (isMoving
                          ? Colors.greenAccent.withAlpha(230)
                          : Colors.pinkAccent.withAlpha(230)),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        animationController.currentState.name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "帧:${animationController.currentFrame + 1}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint("🛑 DeskPetHome 销毁");
    windowManager.removeListener(this); // 🔥 移除监听器
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: buildPet(),
    );
  }
}

import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:path/path.dart' as p;

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:audioplayers/audioplayers.dart'; // (音效)

// [Q&A 历史记录的数据结构]
class QaPair {
  final String question;
  final String answer;

  QaPair(this.question, this.answer);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(400, 400),
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

  await initSystemTray();

  runApp(const DeskPetApp());
}

// ... (省略 _getFallbackIconPath - 没有变化) ...
String _getFallbackIconPath() {
  try {
    String exePath = Platform.resolvedExecutable;
    String exeDir = p.dirname(exePath);
    String icoPath = p.join(exeDir, 'data', 'runner', 'resources', 'app_icon.ico');
    
    if (!File(icoPath).existsSync()) {
      icoPath = p.join(exeDir, 'runner', 'resources', 'app_icon.ico');
    }
    
    if (File(icoPath).existsSync()) {
      return icoPath;
    } else {
      return '';
    }
  } catch (e) {
    debugPrint("❌ 寻找后备图标路径时出错: $e");
    return '';
  }
}


Future<void> initSystemTray() async {
  final SystemTray systemTray = SystemTray();
  
  String? finalIconPath;
  String finalTitle = "桌面宠物";

  // ... (省略平台图标加载逻辑 - 没有变化) ...
  if (Platform.isWindows) {
    final String myCustomIcon = 'assets/images/icon.ico';
    
    try {
      await systemTray.initSystemTray(
        title: finalTitle,
        iconPath: myCustomIcon,
      );
      finalIconPath = myCustomIcon;
      debugPrint("✅ 成功加载自定义图标: $myCustomIcon");
    } catch (e) {
      debugPrint("❌ 自定义图标 '$myCustomIcon' 加载失败: $e");
      
      String fallbackPath = _getFallbackIconPath();
      
      if (fallbackPath.isNotEmpty) {
        debugPrint("ℹ️ 正在尝试使用应用默认图标: $fallbackPath");
        try {
          await systemTray.initSystemTray(
            title: finalTitle,
            iconPath: fallbackPath,
          );
          finalIconPath = fallbackPath;
          finalTitle = "桌面宠物 (后备)";
          debugPrint("✅ 成功加载后备图标");
        } catch (e2) {
          debugPrint("❌ 连后备图标 '$fallbackPath' 都加载失败: $e2");
        }
      } else {
        debugPrint("❌ 找不到后备图标, 托盘功能将不可用。");
      }
    }
  } else {
    final String myCustomIcon = 'assets/images/icon.png';
    try {
      await systemTray.initSystemTray(
        title: finalTitle,
        iconPath: myCustomIcon,
      );
      finalIconPath = myCustomIcon;
      debugPrint("✅ 成功加载自定义图标: $myCustomIcon");
    } catch (e) {
      debugPrint("❌ 自定义图标 '$myCustomIcon' 加载失败: $e");
    }
  }

  if (finalIconPath == null) {
    debugPrint("🛑 托盘图标全部加载失败，无法初始化菜单。");
    return;
  }

  final Menu menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(
      label: '显示/隐藏',
      onClicked: (menuItem) => toggleWindowVisibility(),
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: '退出',
      onClicked: (menuItem) => windowManager.close(),
    ),
  ]);
  await systemTray.setContextMenu(menu);

  // 注册托盘事件
  systemTray.registerSystemTrayEventHandler((eventName) {
    debugPrint("托盘事件: $eventName");
    if (eventName == kSystemTrayEventClick) {
      toggleWindowVisibility();
    } else if (eventName == kSystemTrayEventRightClick) { 
      systemTray.popUpContextMenu();
    }
  });
}


// ... (省略 toggleWindowVisibility - 没有变化) ...
void toggleWindowVisibility() async {
  bool isVisible = await windowManager.isVisible();
  if (isVisible) {
    windowManager.hide();
  } else {
    windowManager.show();
    windowManager.focus();
  }
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

// ... (省略 PetState, FrameAnimationController - 没有变化) ...
enum PetState { 
  idle, 
  walk, 
  drag, 
  click, 
  feed,
  happy,
  // (sad 已移除)
  shock 
}

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
      case PetState.click:
        return 47;
      case PetState.feed:
        return 24;
      case PetState.happy:
        return 10;
      // (sad 已移除)
      case PetState.shock: 
        return 10;
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
  
  // ... (省略所有状态变量 - 它们没有变化) ...
  double x = 100, y = 100;
  bool isDragging = false;
  late Size screenSize;
  double petSize = 400;
  double petScale = 1.0;
  double volume = 0.5;
  late Ticker ticker;
  bool isMoving = false;
  double maxOffset = 400;
  double? targetX, targetY;
  final Random random = Random();
  Duration _lastMoveTime = Duration.zero;
  Duration _randomMoveInterval = const Duration(seconds: 10);
  Duration _currentElapsed = Duration.zero;
  bool isPlayingOneShotAnimation = false; 
  bool showSettingsMenu = false;
  final FrameAnimationController animationController = FrameAnimationController();
  final Map<String, ImageProvider> _imageCache = {};
  bool _imagesLoaded = false;
  bool _didPrecacheOnce = false;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String _debugStatus = "Initializing...";
  bool _showHistoryView = false;
  final Map<String, String> _pendingQuestions = {};
  final List<QaPair> _answeredHistory = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    debugPrint("🔧 DeskPetHome 初始化开始");
    
    adjustVolume(volume); 
    _initializePetPosition();
    _connectWebSocket();
  }

  // (清空 onWindowMoved)
  @override
  void onWindowMoved() {
    // (清空)
  }

  @override
  void onWindowEvent(String eventName) {
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

  // ... (省略 _preloadImages, _initializePetPosition - 没有变化) ...
  Future<void> _preloadImages() async {
    debugPrint("🚀 开始预加载图片...");
    final List<Map<String, dynamic>> states = [
      {'name': 'idle', 'count': 12},
      {'name': 'walk', 'count': 11},
      {'name': 'drag', 'count': 35},
      {'name': 'click', 'count': 47},
      {'name': 'feed', 'count': 24},
      {'name': 'happy', 'count': 10},
      // (sad 已移除)
      {'name': 'shock', 'count': 10}, 
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
  
  // ( 10s 散步逻辑 - Ticker )
  void startPhysicsLoop() {
    debugPrint("🎮 物理循环启动");
    ticker = createTicker((elapsed) {
      _currentElapsed = elapsed;
      if (!mounted) return;

      bool needsRepaint = animationController.updateFrame(elapsed);

      // (10 秒空闲逻辑)
      if (!isMoving &&
          targetX == null &&
          !isDragging &&
          !isPlayingOneShotAnimation) {
        if (elapsed - _lastMoveTime > _randomMoveInterval) {
          movePetRandomly();
        }
      }

      bool moved = false;
      if (!isDragging && targetX != null && targetY != null) {
        // (自动寻路逻辑)
        final dx = targetX! - x;
        final dy = targetY! - y;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance < 1.0) {
          _lastMoveTime = _currentElapsed; // 散步结束, 重置计时器
          
          setState(() {
            isMoving = false;
            targetX = null;
            targetY = null;
            animationController.setState(PetState.idle);
          });
          debugPrint("🎯 到达目标位置");
        } else {
          x += dx * 0.008; // (慢速)
          y += dy * 0.008; 
          moved = true;
        }
      }

      // (原生拖拽逻辑)
      if (moved && !isDragging) {
        x = x.clamp(0, screenSize.width - petSize);
        y = y.clamp(0, screenSize.height - petSize);
        windowManager.setPosition(Offset(x, y));
      }

      if (needsRepaint || moved) { 
        if (mounted) setState(() {});
      }
    });
    ticker.start();
  }

  // ... (省略 movePetRandomly, _connectWebSocket, _handleDisconnect, _handleMessage - 没有变化) ...
  void movePetRandomly() {
    _playSound('walk.mp3'); 

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

  void _connectWebSocket() {
    if (_isConnected) return;
    
    setState(() {
      _debugStatus = "连接到 ws://localhost:8011/ws...";
    });
    debugPrint(_debugStatus);

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:8011/ws'),
      );
      _isConnected = true;
      
      setState(() {
        _debugStatus = "已连接 ✅";
      });
      debugPrint(_debugStatus);

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          debugPrint("❌ WebSocket 错误: $error");
          _handleDisconnect();
        },
        onDone: () {
          debugPrint("ℹ️ WebSocket 连接关闭");
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint("❌ WebSocket 连接失败: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!_isConnected) return;
    
    _isConnected = false;
    _channel = null;
    
    setState(() {
      _debugStatus = "已断开 ❌ 5秒后重连...";
    });
    debugPrint(_debugStatus);
    
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _connectWebSocket();
      }
    });
  }

  void _handleMessage(String message) {
    
    debugPrint("✅ [WebSocket 原始消息] 收到: $message");

    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'];
      final dynamic payload = data;
      final String? reqId = payload['request_id'];

      if (type == 'ai_judge_question') {
        
        final String? question = payload['new_question'];
        
        if (reqId != null && question != null) {
          _pendingQuestions[reqId] = question;
        }
        
        debugPrint("❓ 已解析: 收到新题目 (ID: $reqId)");
        setState(() {
          _debugStatus = "New question loaded.";
        });

      } else if (type == 'ai_judge_result') {
        
        final String judgeAnswer = payload['judge_answer'] ?? "N/A";
        final Map<String, dynamic>? scoreResult = payload['score_result'] as Map<String, dynamic>?;
        final int score = (scoreResult?['score'] as num? ?? 0).toInt();

        final String? question = _pendingQuestions.remove(reqId);

        if (question != null) {
          setState(() {
             _answeredHistory.add(QaPair(question, judgeAnswer));
          });

          debugPrint("=======================");
          debugPrint("  🎯 题目/判题 关联打印");
          debugPrint("  ID: $reqId");
          debugPrint("  Q: $question");
          debugPrint("  A: $judgeAnswer");
          debugPrint("  Score: $score");
          debugPrint("=======================");

        } else {
          debugPrint("⚠️ 收到答案 (ID: $reqId)，但找不到对应的待处理问题。");
        }

        // (sad 已移除)
        if (score >= 2) {
          _triggerHappyAnimation();
        } 
        
      } else if (type == 'ai_validate_final_result') {
          final String status = payload['validation_status'] ?? "UNKNOWN";
          final String feedback = payload['feedback'] ?? "N/A";
          final String? reqId = payload['request_id'];

          debugPrint("=======================");
          debugPrint("  🏆 最终答案验证");
          debugPrint("  ID: $reqId");
          debugPrint("  Status: $status");
          debugPrint("  Feedback: $feedback");
          debugPrint("=======================");

          if (status == "CORRECT") {
            _triggerShockAnimation();
          }
      }

    } catch (e) {
      debugPrint("❌ 处理消息时出错 (非 JSON 或 格式错误): $e");
      setState(() {
        _debugStatus = "Error parsing message.";
      });
    }
  }


  // ... (省略 onTapPet, onTapFeed, _triggerHappyAnimation, _triggerShockAnimation - 它们没有变化) ...
  void onTapPet() {
    if (isPlayingOneShotAnimation) return;
    _playSound('click.mp3');
    debugPrint("👆 点击桌宠");
    isPlayingOneShotAnimation = true;

    setState(() {
      isMoving = false;
      targetX = null;
      targetY = null;
      showSettingsMenu = false;
      animationController.setState(PetState.click);
    });

    final clickDuration = animationController.frameDuration *
        animationController.getFrameCount(PetState.click);

    Future.delayed(clickDuration, () {
      if (mounted && !isDragging && !isMoving && animationController.currentState == PetState.click) {
        setState(() {
          animationController.setState(PetState.idle);
          isPlayingOneShotAnimation = false;
        });
        debugPrint("🎬 click 动画播放完毕，回到 idle");
      }
    });

    _lastMoveTime = _currentElapsed; // 重置计时器
  }
  
  void onTapFeed() {
    if (isPlayingOneShotAnimation) return;
    _playSound('feed.mp3');
    debugPrint("🍲 开始喂食");
    isPlayingOneShotAnimation = true;

    setState(() {
      isMoving = false;
      targetX = null;
      targetY = null;
      showSettingsMenu = false;
      animationController.setState(PetState.feed);
    });

    // (x2 循环)
    final feedDuration = animationController.frameDuration *
        animationController.getFrameCount(PetState.feed) * 2;

    Future.delayed(feedDuration, () {
      if (mounted && !isDragging && !isMoving && animationController.currentState == PetState.feed) {
        setState(() {
          animationController.setState(PetState.idle);
          isPlayingOneShotAnimation = false;
        });
        debugPrint("🎬 喂食动画播放完毕 (x2)，回到 idle");
      }
    });
    _lastMoveTime = _currentElapsed; // 重置计时器
  }
  
  void _triggerHappyAnimation() {
    if (isPlayingOneShotAnimation) return;
    _playSound('happy.mp3');
    debugPrint("😄 触发 Happy 动画");
    isPlayingOneShotAnimation = true;

    setState(() {
      isMoving = false;
      targetX = null;
      targetY = null;
      showSettingsMenu = false;
      animationController.setState(PetState.happy);
    });

    final duration = animationController.frameDuration *
        animationController.getFrameCount(PetState.happy);

    Future.delayed(duration, () {
      if (mounted && !isDragging && !isMoving && animationController.currentState == PetState.happy) {
        setState(() {
          animationController.setState(PetState.idle);
          isPlayingOneShotAnimation = false;
        });
        debugPrint("🎬 Happy 动画播放完毕，回到 idle");
      }
    });
    _lastMoveTime = _currentElapsed; // 重置计时器
  }
  
  // (sad 函数已移除)
  
  void _triggerShockAnimation() {
    if (isPlayingOneShotAnimation) return;
    _playSound('shock.mp3');
    debugPrint("😲 触发 Shock 动画");
    isPlayingOneShotAnimation = true;

    setState(() {
      isMoving = false;
      targetX = null;
      targetY = null;
      showSettingsMenu = false;
      animationController.setState(PetState.shock);
    });

    // (x2 循环)
    final duration = animationController.frameDuration *
        animationController.getFrameCount(PetState.shock) * 2;

    Future.delayed(duration, () {
      if (mounted && !isDragging && !isMoving && animationController.currentState == PetState.shock) {
        setState(() {
          animationController.setState(PetState.idle);
          isPlayingOneShotAnimation = false;
        });
        debugPrint("🎬 Shock 动画播放完毕 (x2)，回到 idle");
      }
    });
    _lastMoveTime = _currentElapsed; // 重置计时器
  }

  
  // [!! 🔥 循环修复 1: 修改 _playSound (one-shot) !!]
  void _playSound(String soundName) {
    // 确保所有“一次性”音效播放完毕后就停止，不循环
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.stop(); 
    try {
      _audioPlayer.play(AssetSource('audio/$soundName'));
      debugPrint("🎵 正在播放 (One-shot): $soundName");
    } catch (e) {
      debugPrint("❌ 播放音效失败 ($soundName): $e");
    }
  }

  // [!! 🔥 循环修复 2: 新增循环播放拖拽声的函数 !!]
  void _playDragSound() {
    // 设置为循环模式
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _audioPlayer.stop(); // 停止上一个声音
    try {
      _audioPlayer.play(AssetSource('audio/drag.mp3'));
      debugPrint("🎵 正在播放 (Loop): drag.mp3");
    } catch (e) {
      debugPrint("❌ 播放音效失败 (drag.mp3): $e");
    }
  }

  // [!! 🔥 循环修复 3: 新增停止循环的函数 !!]
  void _stopDragSound() {
    _audioPlayer.stop();
    // 恢复为“播放完即停”模式，供下次 _playSound 使用
    _audioPlayer.setReleaseMode(ReleaseMode.stop); 
    debugPrint("🎵 停止循环 (drag.mp3)");
  }


  // [!! 🔥 循环修复 4: 修改 onDragStart !!]
  void onDragStart(DragStartDetails details) {
    _playDragSound(); // <-- 1. 立即播放循环音效
    debugPrint("🖱️ 开始原生拖拽 (请求)");
    _lastMoveTime = _currentElapsed; // 2. 立即重置计时器

    setState(() { // 3. 立即设置动画状态
      isDragging = true;
      isMoving = false;
      targetX = null;
      targetY = null;
      isPlayingOneShotAnimation = false;
      showSettingsMenu = false;
      animationController.setState(PetState.drag);
    });

    // 4. 开始拖拽 (非阻塞)
    windowManager.startDragging().then((_) {
      // 5. 拖拽 *结束* 后，这个回调会执行
      debugPrint("🖱️ 原生拖拽结束 (回调)");
      
      _stopDragSound(); // <-- [!! 🔥 循环修复 5: 停止循环音效 !!]

      if (mounted) {
        _lastMoveTime = _currentElapsed; // 重置计时器
        setState(() {
          isDragging = false;
          animationController.setState(PetState.idle);
        });
      }
    });
  }


  // ... (省略 getScaleForState, adjustVolume, adjustPetSize - 它们没有变化) ...
  double getScaleForState(PetState state) {
    switch (state) {
      case PetState.idle:
        return 1.0;
      case PetState.walk:
        return 1.2;
      case PetState.drag:
        return 1.0;
      case PetState.click:
        return 1.1;
      case PetState.feed:
        return 1.1;
      case PetState.happy:
        return 1.1;
      // (sad 已移除)
      case PetState.shock: 
        return 1.1;
    }
  }

  void adjustVolume(double newVolume) {
    setState(() {
      volume = newVolume.clamp(0.0, 1.0);
    });
    _audioPlayer.setVolume(volume); 
    debugPrint("🔊 音量调整为: ${(volume * 100).toInt()}%");
  }

  void adjustPetSize(double newScale) {
    setState(() {
      petScale = newScale.clamp(0.5, 2.0);
      petSize = 400 * petScale;
    });
    windowManager.setSize(Size(petSize, petSize));
    debugPrint("📏 桌宠大小调整为: ${petScale}x (${petSize}px)");
  }

  // ... (省略 toggleSettingsMenu, onMinimizePet, buildSettingsButton, buildSettingsMenu - 它们没有变化) ...
  
  void toggleSettingsMenu() {
    setState(() {
      showSettingsMenu = !showSettingsMenu;
      if (showSettingsMenu && _showHistoryView) {
        _showHistoryView = false;
      }
    });
    debugPrint("⚙️ 设置菜单: ${showSettingsMenu ? '打开' : '关闭'}");
  }
  
  void onMinimizePet() {
    debugPrint("🔽 最小化到托盘");
    windowManager.hide();
    setState(() {
      showSettingsMenu = false;
    });
  }

  Widget buildSettingsButton() {
    return Positioned(
      top: 0,
      right: 0,
      child: GestureDetector(
        onTap: toggleSettingsMenu,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(200),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 4,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.settings,
            size: 16,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
  
  Widget buildSettingsMenu() {
    if (!showSettingsMenu) return const SizedBox.shrink();

    return Positioned(
      top: 30,
      right: 0,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 6,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '⚙️ 设置',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            const Text(
              '📏 桌宠大小',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: petScale,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      label: '${petScale.toStringAsFixed(1)}x',
                      onChanged: adjustPetSize,
                      activeColor: Colors.pinkAccent,
                    ),
                  ),
                ),
                SizedBox(
                  width: 35,
                  child: Text(
                    '${petScale.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '🔊 音量',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(volume * 100).toInt()}%',
                      onChanged: adjustVolume, 
                      activeColor: Colors.greenAccent.shade700,
                    ),
                  ),
                ),
                SizedBox(
                  width: 35,
                  child: Text(
                    '${(volume * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            GestureDetector(
              onTap: onTapFeed,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🍲', style: TextStyle(fontSize: 11)),
                    SizedBox(width: 6),
                    Text(
                      '喂食',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            GestureDetector(
              onTap: onMinimizePet,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 12),
                    SizedBox(width: 6),
                    Text(
                      '最小化',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: _isConnected ? Colors.green : Colors.red,
                  size: 12,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _debugStatus,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                      fontWeight: _isConnected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget buildPet() {
    if (!_imagesLoaded) {
      // ... (省略加载中的 UI) ...
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
    final scale = getScaleForState(animationController.currentState);

    // (原生拖拽)
    return GestureDetector(
      onTapDown: (_) => onTapPet(),
      onPanStart: onDragStart, 
      child: Container(
        // ... (省略内部的 Container, ClipRRect, Image 等 - 它们没有变化) ...
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
              ? Transform.scale(
                  scale: scale,
                  child: Image(
                    image: cachedImage,
                    width: petSize,
                    height: petSize,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint("❌ 图片加载失败: $currentPath");
                      _imageCache.remove(currentPath);
                      return Image.asset(
                        'assets/images/idle/idle_001.png',
                        width: petSize,
                        height: petSize,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
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
    windowManager.removeListener(this);
    ticker.dispose();
    _channel?.sink.close();
    _audioPlayer.dispose(); // (音效)
    super.dispose();
  }

  // ... (省略 buildHistoryButton, buildHistoryView - 它们没有变化) ...
  Widget buildHistoryButton() {
    return Positioned(
      top: 0,
      left: 0,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showHistoryView = !_showHistoryView;
            if (_showHistoryView && showSettingsMenu) {
              showSettingsMenu = false;
            }
          });
          debugPrint("📖 历史视图: ${_showHistoryView ? '打开' : '关闭'}");
        },
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(200),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 4,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Icon(
            _showHistoryView ? Icons.close_rounded : Icons.view_list_rounded,
            size: 16,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
  
  Widget buildHistoryView() {
    if (!_showHistoryView) return const SizedBox.shrink();

    // 1. 过滤数据
    final yesQuestions = _answeredHistory
        .where((pair) => pair.answer == "是")
        .map((pair) => pair.question)
        .toList();
        
    final noQuestions = _answeredHistory
        .where((pair) => pair.answer == "否")
        .map((pair) => pair.question)
        .toList();

    // 2. 构建视图
    return Positioned(
      top: 40,
      left: 10,
      right: 10,
      bottom: 40,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(245),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // --- "Yes" 列表 ---
                Expanded(
                  child: ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "Yes (是)",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.green, height: 1),
                      if (yesQuestions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            "(暂无)",
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ...yesQuestions.map((q) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(
                            "Q: $q",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        )),
                    ],
                  ),
                ),
                
                const VerticalDivider(color: Colors.grey, width: 20),

                // --- "No" 列表 ---
                Expanded(
                  child: ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "No (否)",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.red, height: 1),
                      if (noQuestions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            "(暂无)",
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ...noQuestions.map((q) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(
                            "Q: $q",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        )),
                    ],
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        alignment: Alignment.center,
        children: [
          buildPet(),
          buildSettingsButton(),
          buildSettingsMenu(),
          
          buildHistoryView(),
          buildHistoryButton(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'dhamma_screen.dart';
import 'dubbing_screen.dart';
import 'fruit_story_screen.dart';
import 'long_to_short_screen.dart';
import 'recap_screen.dart';
import 'splitter_screen.dart';
import 'subtitle_screen.dart';

class _Tool {
  final String icon;
  final String title;
  final String desc;
  final Widget Function() build;
  const _Tool(this.icon, this.title, this.desc, this.build);
}

/// Grid of all creator tools (Studio99 feature set minus the removed ones).
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  static final _tools = <_Tool>[
    _Tool('🎬', 'Recap Translate',
        'နိုင်ငံခြား video → မြန်မာစာတန်း + dubbing (Gemini)', () => const RecapScreen()),
    _Tool('🎙️', 'Dubbing Studio',
        'အသံသွင်း → video နဲ့ ရော/အစားထိုး', () => const DubbingScreen()),
    _Tool('💬', 'Myanmar Subtitle',
        'SRT စာတန်း မြန်မာဖောင့်နဲ့ burn', () => const SubtitleScreen()),
    _Tool('🙏', 'Dhamma Studio',
        'တရားအသံ + ပုံ + ခေါင်းစဉ် → video', () => const DhammaScreen()),
    _Tool('📝', 'Original Recap',
        'ကိုယ့် video → မြန်မာ storytelling script (Gemini)',
        () => const RecapScreen()),
    _Tool('✂️', 'Video Splitter',
        'မိနစ်အလိုက် အပိုင်းတွေ ဖြတ်', () => const SplitterScreen()),
    _Tool('📱', 'Long to Short',
        'video ရှည် → 9:16 shorts တွေ', () => const LongToShortScreen()),
    _Tool('🍓', 'Fruit Story',
        'ပုံ + motion + အသံ → story video', () => const FruitStoryScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🛠️ Creator Tools')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _tools.length,
        itemBuilder: (context, i) {
          final t = _tools[i];
          return Card(
            elevation: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => t.build()),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.icon, style: const TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(t.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(t.desc,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

# VideoTool — Flutter + FFmpegKit starter

မြန်မာ UI ပါတဲ့ video tool အခြေခံပရောဂျက်။ studio99 လို အက်ပ်တွေရဲ့ တည်ဆောက်ပုံ
(Flutter + FFmpegKit + RNNoise) ကို အစအဆုံး ကိုယ်တိုင်ရေးထားတာ။

## ပါဝင်တဲ့ လုပ်ဆောင်ချက်တွေ

- **ဗီဒီယိုရွေးမယ်** — ဖုန်းထဲက video ရွေးပြီး FFprobe နဲ့ ကြာချိန်/resolution/အရွယ်အစား ပြမယ်
- **အသံဆူညံမှုဖယ်ရှားမယ်** — RNNoise (`arnndn`) filter နဲ့ နောက်ခံဆူညံသံဖယ်မယ်၊ ရုပ်ထွက်မပြောင်း
- **ဗီဒီယိုချုံ့မယ်** — H.264 CRF 28 နဲ့ ဖိုင်သေးအောင်ချုံ့မယ်
- **အသံပဲထုတ်မယ်** — အသံလမ်းကြောင်းပဲ m4a အဖြစ်ထုတ်မယ်
- Progress bar + ရပ်မယ် ခလုတ်၊ ပြီးရင် share လုပ်လို့ရမယ်၊ FFmpeg log ကြည့်လို့ရမယ်

## တည်ဆောက်ပုံ

```
lib/
  main.dart                  — app entry, dark Material theme
  screens/home_screen.dart   — UI (မြန်မာ)
  services/ffmpeg_service.dart — FFmpegKit wrapper (probe/run/cancel)
assets/models/
  cb.rnnn                    — RNNoise မော်ဒယ် (open model, NOTICE.txt ကြည့်)
  NOTICE.txt                 — မော်ဒယ် လိုင်စင်မှတ်စု
android/                     — flutter create နဲ့ ထုတ်ထားတဲ့ Android scaffold
```

## Build လုပ်နည်း (PC မလိုတဲ့နည်း)

ဒီ VM မှာ Flutter + Android SDK သွင်းပြီးသား (`~/workspace/.sdks/`) —

```bash
export PATH="$HOME/workspace/.sdks/flutter/bin:$PATH"
export JAVA_HOME="$HOME/workspace/.sdks/jdk17"
export ANDROID_SDK_ROOT="$HOME/workspace/.sdks/android-sdk"
cd ~/workspace/videotool-flutter
flutter pub get
flutter build apk --debug
# APK: build/app/outputs/flutter-apk/app-debug.apk
```

## မှတ်စုများ

- `ffmpeg_kit_flutter_new` (FFmpegKit fork, full-gpl အပါ) သုံးထားလို့ **GPL v3** သက်ရောက်တယ် —
  ကိုယ်တိုင်သုံးတာ/စမ်းတာက ပြဿနာမရှိ၊ Play Store တင်မယ်ဆို လိုင်စင်အကြောင်းလေ့လာပါ။
- RNNoise မော်ဒယ် (`cb.rnnn`) က copyright မသက်ရောက်တဲ့ open model —
  အသေးစိတ် `assets/models/NOTICE.txt` မှာ။
- Debug APK ကို ဖုန်းမှာ တိုက်ရိုက်သွင်းလို့ရတယ် (unknown sources ခွင့်ပြုရန်)။

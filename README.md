# ComfyUI Remote

A Flutter mobile app for remotely controlling ComfyUI from your phone or tablet.

<img src="screenshots/home.jpg" width="180"> <img src="screenshots/generate_top.jpg" width="180"> <img src="screenshots/generate_bottom.jpg" width="180"> <img src="screenshots/gallery.jpg" width="180">

---

## Features

### 🔌 Power & Connectivity
- Turn your PC on/off via **Tuya smart plug**
- **Hard reset** (power cycle) for frozen PC
- Real-time PC status monitoring (Offline → Booting → Online → ComfyUI Ready)
- Remote **SSH control** — start ComfyUI, view logs, shutdown PC

### 🎨 Image Generation
- 4 LoRA slots with strength sliders
- Sampler, scheduler, steps, CFG, denoise controls
- Resolution presets including **RedMagic 10S Pro** wallpaper sizes
- **Upscale toggle** (RealESRGAN x2 via UltimateSDUpscale)
- Batch generation (up to 50 images)

### 🖼️ Gallery
- Browse locally saved images and ComfyUI history
- Swipeable fullscreen viewer with **pinch & double-tap zoom**
- Multi-select delete
- Load generation settings from image PNG metadata

### ⚙️ Settings & Persistence
- Settings saved to `Downloads/ComfyUI/settings.json`
- Workflow embedded in saved PNGs for settings recovery
- Tablet layout with side navigation rail (iPad support)

---

## Screenshots

| Home | Generate (top) | Generate (bottom) | Gallery |
|------|---------------|------------------|---------|
| <img src="screenshots/home.jpg" width="180"> | <img src="screenshots/generate_top.jpg" width="180"> | <img src="screenshots/generate_bottom.jpg" width="180"> | <img src="screenshots/gallery.jpg" width="180"> |

---

## Planned Features

### 🔌 Networking
- [ ] **Local ComfyUI detection** — auto-discover ComfyUI instances on the local network (current version requires Tailscale IP)
- [ ] **Multi-instance selector** — detect multiple ComfyUI machines on the network and switch between them by name
- [ ] **mDNS/Bonjour discovery** — zero-config connection without manually entering IP addresses
- [ ] **Connection profiles** — save multiple server configurations and switch quickly

### 🎨 Generation
- [ ] **LoRA strength sliders** — individual strength bar under each LoRA selector in the UI
- [ ] **Custom resolution input** — enter any width/height instead of fixed presets
- [ ] **Image to video** — send generated images directly to Wan 2.2 I2V workflow
- [ ] **Text to video** — T2V workflow support from the generate screen
- [ ] **Prompt history** — save and reuse previous prompts
- [ ] **Wildcard support** — random prompt variations
- [ ] **Generation queue** — queue multiple different prompts and run them sequentially

### 🔔 Notifications
- [ ] **Push notifications** — notify when image generation is complete
- [ ] **Background notifications** — status updates when app is minimized
- [ ] **Generation progress** — live step counter during generation

### 🖼️ Gallery
- [ ] **iPad split view** — side-by-side generate and gallery panels
- [ ] **Image tagging** — tag and filter generated images
- [ ] **Favorites** — mark and filter favorite generations

### ⚙️ Management
- [ ] **Model manager** — browse and download models directly from the app
- [ ] **LoRA browser** — preview and manage installed LoRAs
- [ ] **ComfyUI workflow import** — load custom workflows from JSON files

---

## Requirements

- Flutter 3.x+
- Android 10+ or iOS 16+
- ComfyUI running on a PC accessible via Tailscale or local network
- Tuya smart plug (EU region) for power control
- SSH access to the PC

---

## Setup

### 1. Clone the repo

```bash
git clone https://gitlab.com/Ithoroo/comfyui-mobile-remote.git
cd comfyui-mobile-remote
flutter pub get
```

### 2. Configure the app

Open the app and go to **Settings** (gear icon), fill in:

| Setting | Description |
|---|---|
| ComfyUI URL | e.g. `http://100.82.84.36:8000` |
| SSH Host | Tailscale IP of your PC |
| SSH User | Your Windows username |
| SSH Password | Your Windows password |
| Tuya Client ID | From Tuya IoT Platform |
| Tuya Client Secret | From Tuya IoT Platform |
| Tuya Device ID | Your smart plug device ID |

### 3. Tuya setup

1. Create an account at [iot.tuya.com](https://iot.tuya.com)
2. Create a Cloud Project (EU region)
3. Link your smart plug device
4. Copy Client ID, Client Secret and Device ID to app settings

### 4. SSH setup

The app uses SSH to:
- Check if PC is reachable
- Start ComfyUI
- View ComfyUI logs
- Shutdown PC

On Windows enable OpenSSH Server in **Settings → Optional Features → OpenSSH Server**.

### 5. iOS only — allow HTTP

Add this to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

---

## Building

### Android

```bash
flutter build apk --release
```
APK at `build/app/outputs/flutter-apk/app-release.apk`

### iOS (requires Mac + Xcode)

```bash
flutter build ios
open ios/Runner.xcworkspace
```

---

## Project Structure

```
lib/
├── main.dart                   # App entry, navigation shell (phone/tablet)
├── screens/
│   ├── home_screen.dart        # PC power control and status
│   ├── generate_screen.dart    # Image generation UI
│   ├── gallery_screen.dart     # Local and remote image gallery
│   └── settings_screen.dart    # App configuration
└── services/
    ├── settings_service.dart   # SharedPreferences wrapper
    ├── tuya_service.dart       # Tuya smart plug API
    ├── ssh_service.dart        # SSH commands
    ├── comfy_service.dart      # ComfyUI API + workflow builder
    ├── generation_prefs.dart   # Generation settings persistence
    └── png_metadata.dart       # PNG tEXt chunk reader/writer
```

---

## ComfyUI Workflow

The app builds a clean API-format workflow supporting:
- `CheckpointLoaderSimple`
- Up to 4 chained `LoraLoader` nodes
- `CLIPTextEncode` (positive + negative)
- `EmptyLatentImage`
- `KSampler` (with denoise)
- `VAEDecode`
- `SaveImage`
- Optional `UltimateSDUpscale` with RealESRGAN_x2

---

## Notes

- Images saved to `Downloads/ComfyUI/` with embedded workflow metadata
- Settings loaded from any generated image via Gallery → fullscreen → tune icon
- Tested on **RedMagic 10S Pro** (Android 16) and **iPad**

---

## License

MIT
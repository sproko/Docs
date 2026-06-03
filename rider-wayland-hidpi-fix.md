# Fixing blurry/pixelated JetBrains Rider on Hyprland (Wayland + fractional scaling)

## Symptom
Rider's UI (and other JetBrains IDEs) looks soft / pixelated on Hyprland.

## Cause
The monitor uses **fractional scaling** (here: `scale: 1.25`). By default the bundled
JetBrains Runtime (JBR) renders through **XWayland**, which draws at 1× and lets the
compositor bitmap-upscale to 1.25× → everything turns blurry.

Confirm your scale:
```bash
hyprctl monitors | grep -iE "scale|^Monitor"
```

## Fix — enable native Wayland rendering in the JBR
Requires a recent JBR (this machine: **JBR 25**, Rider 2026.1). Check:
```bash
/opt/rider/jbr/bin/java -version   # want JBR 21+, ideally 24/25
```

Add `-Dawt.toolkit.name=WLToolkit` to Rider's **custom** VM options. Two ways:

**A. Via the IDE (safest)**
`Help → Edit Custom VM Options…` → add this line at the end → restart:
```
-Dawt.toolkit.name=WLToolkit
```

**B. By hand**
Custom VM options live at `~/.config/JetBrains/Rider<version>/rider64.vmoptions`
(e.g. `~/.config/JetBrains/Rider2026.1/rider64.vmoptions`).
Start from the bundled defaults so you don't drop heap settings:
```bash
cp /opt/rider/bin/rider64.vmoptions ~/.config/JetBrains/Rider2026.1/rider64.vmoptions
printf '\n-Dawt.toolkit.name=WLToolkit\n' >> ~/.config/JetBrains/Rider2026.1/rider64.vmoptions
```

Then **fully quit and relaunch** (VM options only apply on a fresh start):
```bash
pkill -f /opt/rider/bin/rider
setsid -f rider /path/to/your/project
```

## Verify it worked
- UI text is crisp at the fractional scale.
- Rider stays alive after launch:
  ```bash
  pgrep -f /opt/rider/bin/rider && echo alive
  ```
- The launch log has **no** `WLToolkit`/`wayland` exceptions
  (routine `ClassNotFoundException` for optional plugins and the
  `jb.station.sock` discovery warning are normal — ignore them).

## Notes / fallback
- Native Wayland in the JBR is solid but newer; if you hit oddities (stray popups,
  screenshot tools, a misbehaving dialog), remove the line to fall back to XWayland.
- **XWayland fallback for crispness** (more invasive — affects all X11 apps): set
  `xwayland { force_zero_scaling = true }` in `hyprland.conf`, then tell the JBR to
  scale itself via `-Dsun.java2d.uiScale.enabled=true -Dsun.java2d.uiScale=1.25`.
  Prefer native Wayland over this when it works.
- This is per-IDE. Repeat the VM-option step for other JetBrains tools, and re-apply
  after a major version bump if the config dir name changes (`Rider2026.1` → next).

---
*Environment when written: CachyOS, Hyprland/Wayland, HDMI-A-2 @ 2560x1440 scale 1.25,
Rider 2026.1 / JBR 25, install at `/opt/rider`.*

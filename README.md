# Echo Hunt

A macOS game played on the trackpad surface, by feel. A target is hidden
somewhere on your trackpad and **the screen never shows you where it is** — you
find it through haptic feedback alone.

## Requirements

- A Mac with a **Force Touch trackpad** (built-in, 2015 or newer, or a Magic
  Trackpad 2). The game reads the trackpad surface directly; a mouse won't work.
- **macOS 12+**, and Xcode command line tools (`xcode-select --install`).
- **System Settings → Trackpad → "Force Click and haptic feedback" must be ON.**
  Without it you'll see the game but feel nothing, which is the whole game.

## Build and run

```bash
git clone https://github.com/olehmisar/echo-hunt.git
cd echo-hunt
./build.sh
open build/EchoHunt.app
```

`build.sh` compiles the sources with `swiftc` into `build/EchoHunt.app` and
ad-hoc signs it. There are no dependencies and nothing is downloaded.

Because you built it locally it carries no download quarantine flag, so it opens
without any Gatekeeper warning.

To build a universal (Intel + Apple silicon) binary for sharing instead:

```bash
./package.sh          # produces dist/EchoHunt.zip
```

## How to play

| Input | Feedback | Reads as |
| --- | --- | --- |
| Drag one finger | Taps repeat faster as you close in, and firm up when you're within 0.22 | A geiger counter — coarse, always on |
| Two fingers | A ping, then one thump after a delay proportional to distance | Sonar — slow, but a precise fix |
| Near a decoy | The single tick becomes a stuttering double-tick | A texture you learn to distrust |
| Force click / space | Dig | — |

Your finger is drawn on screen. The target never is. Wrong digs stay on the
board as red crosses and cost points, so they're information you paid for.
Five rounds. **Esc** opens the menu.

## How it works

The trackpad can only produce discrete taps — there is no continuous vibration
mode — so the only expressive channels are **rhythm** and **timing**, and the
game is built entirely out of those two.

- **Haptics** use the public `NSHapticFeedbackManager`. No private APIs.
- **Input** uses `allowedTouchTypes = [.indirect]`, which reports each contact
  as an absolute normalized 0–1 coordinate on the pad. The pad is a map, not a
  pointing device.
- **Fullscreen isn't cosmetic**: AppKit routes indirect touch events through
  window focus, so touches stop arriving if focus drifts. Covering the screen
  keeps the pad ours.
- **Pointer capture** (`CGAssociateMouseAndMouseCursorPosition`) stops your
  finger from dragging the cursor across the screen while you hunt. It's
  released whenever a menu opens or the app loses focus, so the pointer can
  never be left stranded.

## Layout

```
Sources/
  main.swift            NSApplication setup, fullscreen window, pointer state
  GameView.swift        input, sonar scheduling, all drawing
  Game.swift            pure game model — targets, decoys, scoring
  Menu.swift            menu screens and their items
  Haptics.swift         tap and burst primitives
  PointerCapture.swift  game-style cursor capture
build.sh                local build
package.sh              universal build + zip for distribution
sign.sh                 Developer ID signing + notarization (needs a paid cert)
```

`Game.swift` has no UI dependencies, so the rules can be exercised headlessly.

## License

MIT

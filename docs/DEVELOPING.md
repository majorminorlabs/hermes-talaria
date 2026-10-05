# Develop and test Talaria

Open `Hermes.xcodeproj`, select the **Hermes** scheme and an iPhone simulator.
The Xcode project/targets retain technical Hermes names. Normal launch uses the
Studio bridge; explicit Simulation mode and test fixtures are separate.

```sh
xcodebuild -project Hermes.xcodeproj -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO test
cd hermes-mobile-bridge
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/python -m pytest -q
```

Personal signing belongs in ignored `Signing.local.xcconfig`; copy
`Config/Signing.example.xcconfig` and set your Team locally. The current shared build configuration and release artifacts contain no personal
Team, certificate or provisioning material. Public distribution uses a separate
fresh-root repository; see [public release handoff](PUBLIC_RELEASE_HANDOFF.md).

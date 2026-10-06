# Develop and test Talaria

Open `Hermes.xcodeproj`, select the **Hermes** scheme and an iPhone simulator.
The Xcode project/targets retain technical Hermes names. Normal launch uses the
Studio bridge; explicit Simulation mode and test fixtures are separate.

```sh
xcodebuild -project Hermes.xcodeproj -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -parallel-testing-enabled NO test
cd hermes-mobile-bridge
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/python -m pytest -q
```

Personal signing belongs in ignored `Signing.local.xcconfig`; copy
`Config/Signing.example.xcconfig` and set your Team locally. The current shared build configuration and release artifacts contain no personal
Team, certificate or provisioning material. The public repository retains its sanitized history; private development history
is not imported. Set TALARIA_APP_BUNDLE_ID locally for a different app identity.

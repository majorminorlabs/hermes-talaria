# Attachments and dictation

The existing conversation composer now offers Files, Photo Library and Camera
when the connected bridge advertises `attachments`; Photo Library and Camera also require `imageUpload`. Voice input is native
speech-to-text and needs no Hermes audio capability. Keychain pairing is unchanged.

## Upload contract and limits

`POST /mobile/v1/attachments` requires application authentication, `chat.control`,
an authorized conversation, a simple filename, an allowed MIME type and base64
bytes. It returns a generated opaque `upload_id` and artifact metadata, never a
Studio destination path. A run submits up to four distinct IDs using
`POST /conversations/{id}/runs {text,attachment_ids}`. Files are attached through
Hermes' `file.attach`, images through `image.attach_bytes`, PDFs through `pdf.attach`.
Only the selected conversation receives them. A file-only message gets a short
ordinary inspection prompt.

Supported formats:

- PNG, JPEG, WebP and GIF, with matching magic bytes.
- PDF, with matching signature; Hermes renders a bounded preview of the first
  five pages. The prompt identifies that preview limit. Poppler (`pdftoppm`) must
  be available in Hermes' runtime PATH.
- UTF-8 text/Markdown/CSV/TSV, JSON (validated), and common code/config files:
  Python, Swift, JavaScript/TypeScript, C/C++, Rust, Go, Java/Kotlin, Ruby, shells,
  CSS/HTML/XML, YAML/TOML and SQL. Binary archives/executables are rejected.

Maximum 10 MiB per file (a Studio may configure a smaller limit), four files per
message, 40 MiB pending per conversation and 256 MiB total bridge staging. Empty
files, unknown fields/types, invalid base64, control characters, separators and
path traversal in filenames are rejected. Direct upload MIME and content are
checked independently of the picker.

Bridge staging is under its private `state/uploads/`: directory `0700`, generated
filenames, files `0600`. Ready uploads expire after 24 hours. Submitted staging
expires after seven days. Cleanup runs at startup, during staging and in the
five-second maintenance loop; it removes staging and its artifact metadata. Hermes'
canonical attachment copies/history follow Hermes' own retention policy; bridge
cleanup does not delete that history. There is no arbitrary filesystem browser.

Upload and send operations have independent idempotency keys and never automatically
retry after an uncertain outcome. A consumed upload cannot be submitted to another
run or conversation. Attachments stay visible/editable in the composer until a
confirmed send; removing one before send leaves any previously staged copy to expire.
Payload bytes are composer-only and excluded from encoded transcripts/checkpoints.

## Native photo and camera behavior

PhotosPicker supports up to four selections without granting broad library access.
Selected photos and new camera captures become real JPEG bytes with thumbnails and
remove controls before sending. Images are kept at practical resolution, bounded to
4096 pixels on the longest edge and JPEG quality 0.9; sources above 30 MiB or encoded
uploads above 10 MiB fail with a clear error. Files use security-scoped access only
while copying the selected bytes.

Camera capture uses the native UIImagePickerController preview/Use Photo flow.
Cancellation adds nothing. Unavailable cameras and denied permission produce a
Settings guidance error. `NSCameraUsageDescription` is supplied for both app builds.

## Voice input

The microphone control starts/stops `AVAudioEngine` plus `SFSpeechRecognizer`.
Partial recognized words populate the ordinary composer; Stop preserves that text
for editing, Cancel restores the pre-dictation draft, and Send uses the normal chat
path. No microphone audio is uploaded to the bridge. Leaving the conversation or
backgrounding the app cancels capture and releases the audio session.

The app requests microphone and speech-recognition permission, checks recognizer
availability, and reports denied or unavailable states. It sets
`requiresOnDeviceRecognition` when `supportsOnDeviceRecognition` is true. Other
languages/devices use Apple's network recognition and show that status while
listening. See [Apple's on-device recognition contract](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition).
This is short composer dictation, not a voice call or recorded-audio attachment.
The app supplies `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.

## Validation

Bridge tests cover staging, actual send attachment routing, images, authentication,
size/MIME/name/path rejection, cleanup, bridge restart and duplicate/idempotent
selection. Swift transport tests check upload-to-send ID mapping and excluded
payload persistence. Installed-Hermes integration uses an isolated home and local
model. Physical camera/microphone/PhotosPicker validation requires an unlocked
phone; current results are recorded in BOT_MODE_VALIDATION.md.


Studio setup for PDFs: install Homebrew `poppler` when `pdftoppm` is absent
(`brew install poppler`). The existing service launcher includes `/opt/homebrew/bin`
and `/usr/local/bin`; no shell export is needed. In this sprint the package was
installed on the Studio and a live one-page PDF upload returned the exact visual
marker through Hermes. The regression also checks the native first/last page bounds.


### Physical acceptance follow-up (2026-10-03)

The current signed app was installed over the existing physical iPhone app. Bot
creation proved the phone still reaches the Studio over its configured private
Tailscale HTTPS connection while Wi-Fi is active. The device locked again before
media/dictation tests could start. Files, Photo Library, camera permission/capture,
real microphone partial transcription, stop/cancel and edited-text receipt remain
pending physical acceptance; no media pass is inferred from bot creation.

### Completed physical acceptance (2026-10-04)

Files, Photo Library, new camera capture and dictation all passed on the iPhone 15
Pro Max. Each file/image had a composer preview and was consumed once by the
temporary bot's canonical chat. The Files fixture was 74 bytes; Hermes read its
exact marker. Photo Library used an inspected harmless logo (196,659-byte JPEG)
through the native selected-items-only picker. Camera permission, Take Picture,
preview and Use Photo produced a new harmless surface image (990,984-byte JPEG),
which Hermes described. Upload limits and supported types are unchanged.

Speech Recognition and microphone permission were granted. The initial speech
authorization exposed a real actor-isolation crash on Apple's background callback.
The callback boundary was fixed and covered by a background-queue regression;
the installed fixed build completed native speech capture without crashing.
The UI showed **Listening · on device**, with partial text visible before Stop.
Cancel returned to the editable composer, and a second capture succeeded.

The acoustic fixture was the spoken sentence “This is a physical iPhone voice input
test.” Codex also played that sentence aloud using the Studio's `say` command; it
entered through the real phone microphone, with no audio injection into the app.
The recognized text remained editable. After inserting the test instruction, the
exact native Hermes user message was:

```text
Edited before sending. Reply SPRINT_PHONE_VOICE_OK.This is a physical iPhone voice input test
```

Hermes returned `SPRINT_PHONE_VOICE_OK`. The voice run had no attachment IDs or tool
calls; the conversation's upload count stayed at three before/after dictation.
Apple network recognition was not exercised because this device supported on-device
recognition. Denied-permission settings were not reset to manufacture another test.

Backgrounding during the Files run and returning after four seconds preserved the
conversation, reconciled completion and rendered a single assistant reply and
single attachment. Relaunch persistence also passed in bot and Research tests.
Wi-Fi through the private Tailscale HTTPS route worked; cellular was not repeated.
The temporary bot was hidden using native semantics, retaining its history. The
iCloud Files fixture was removed; consumed staging data follows the seven-day
cleanup policy. No test media or device evidence is committed. Result-bundle paths
and test totals are in [BOT_MODE_VALIDATION.md](BOT_MODE_VALIDATION.md).

### Talaria post-design follow-up (2026-10-04)

Native dictation was repeated successfully on the Talaria build, with a real
spoken sentence at the iPhone microphone. Cancel, partial on-device recognition,
Stop, editing, ordinary text send and return from background were exercised.
Hermes received the captured edited composer text after normal whitespace
trimming. Upload rows stayed at seven before/after this voice run; no audio was
staged. Evidence: `<private-local-evidence>`.
Camera and Photo Library were not repeated in this focused post-design pass;
their earlier actual physical results above remain the evidence for those paths.
See TALARIA_REGRESSION_VALIDATION.md for the final Files and release results.

Files was also repeated on Talaria: native picker and preview, 74-byte text upload,
Hermes marker read-back and background/foreground event replay all passed. The
reply and attachment appeared once. Evidence:
`<private-local-evidence>`.

The owned iCloud fixture was removed after acceptance. Its one consumed upload
follows the existing seven-day staging policy; hiding the temporary bot preserved
all ten native messages. No photos/files/recordings or pairing material are committed.

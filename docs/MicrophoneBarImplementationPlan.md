# Microphone Input Bar Implementation Plan

## Overview
- replace the existing text input field in `ChatView` with a microphone-first interaction that records voice input and submits transcripts to the chat model.
- long press on the microphone pill starts on-device speech recognition; releasing the press stops capture, finalizes the transcript, and kicks off a normal chat request.
- ensure we request speech + microphone permissions, surface recording affordances, and preserve current chat behavior once text is available.

## Goals
- deliver a single-tap/press voice entry point while keeping the downstream chat flow untouched.
- meet Apple on-device speech requirements (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`) and gracefully handle unsupported locales/devices.
- provide clear UI states for idle, recording, permission denied, and transcription in-progress.

## Out of Scope
- maintaining a fallback text keyboard UI.
- adding streaming/partial transcription display (single final transcript is enough initially).
- caching audio data or supporting background recording.

## UX & Interaction Flow
1. Idle: microphone bar visible with instruction label (e.g., "Hold to speak"). Disabled when downloads/streaming already in progress.
2. Long press begin: vibrate/light animation, permission request if not yet granted, start recognition session with warmup UI.
3. Long press end: stop audio engine, finish recognition, show a short "Transcribing…" state before calling existing `send` pipeline.
4. Error states: present inline messages for denied permissions, recognition failures, or short utterances. Allow retry without leaving the chat.

## Technical Plan
### UI Restructure (`lfm2oniosPackage/Sources/lfm2oniosFeature/ChatView`)
- Remove the text field + send button stack; create a new `MicrophoneInputBar` view that exposes callbacks `onStartRecording()` and `onFinishRecording()`.
- Track local state inside `ChatView` for recording status, permission errors, and the latest transcript. Gate `onStartRecording` when `isStreaming` true.
- Trigger the existing message sending logic (`conversationManager?.send(message:)`) using the transcript string once available; preserve scroll-to-bottom behavior and existing streaming lines.

### Speech Recognition Service (`lfm2oniosPackage/Sources/lfm2oniosFeature/`)
- Introduce a `SpeechRecognitionService` actor that wraps `AVAudioEngine` + `SFSpeechRecognizer` for on-device capture.
- Responsibilities: permission handling, session lifecycle, error propagation, returning the final transcript.
- Configure with locale from selected model or system default; ensure `supportsOnDeviceRecognition` is true before starting, otherwise emit a user-facing error.
- Provide async APIs (e.g., `func start() async throws -> SpeechSession` and `func stop() async -> String?`) to integrate cleanly with Swift concurrency.

### Permissions & Configuration
- Update the app target Info.plist (via the `Config` xcconfig/Info.plist workflow) to include `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` strings.
- Request `SFSpeechRecognizer` authorization during first press; surface denial messaging and disable the mic bar until settings change.
- Ensure the microphone session uses `.playAndRecord` with `.duckOthers` to avoid fighting with the model audio output if used later.

### State & Error Handling
- Add user-visible toasts or inline text for the following cases: permission denied, recognition unavailable, recognition timeout (< 0.5s speech), generic failure.
- Log failures via `AppLogger` for telemetry parity with download/model events.
- Reset state after successful send to keep the bar responsive.

### Testing Strategy
- Add unit coverage in `lfm2oniosPackage/Tests/lfm2oniosFeatureTests/` for `SpeechRecognitionService` mocking out `SFSpeechRecognizer`/`AVAudioEngine` using dependency injection.
- Update existing chat tests (if any) to cover the `send` pipeline triggered by transcripts.
- Add a new UI test in `lfm2oniosUITests/` that simulates permission granted, long press interaction, and ensures the transcript message appears in the conversation log.

### Tooling & Integration
- Update the simulator smoke test script to mention holding the mic button instead of typing text.
- Verify `xcodebuild … test` remains green locally; note any simulator-specific speech APIs requiring entitlements.

## Hierarchical Implementation Checklist
- [x] Project setup
    - [x] Confirm Info.plist strings (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) are sourced via `Config` xcconfigs
    - [x] Audit entitlements/settings for on-device speech recognition support
- [x] UI implementation
    - [x] Replace text input stack in `ChatView` with `MicrophoneInputBar`
    - [x] Provide idle/recording/transcribing visuals and accessibility labels
    - [x] Wire `MicrophoneInputBar` callbacks into chat send pipeline
- [x] Speech recognition service
    - [x] Create `SpeechRecognitionService` actor encapsulating `AVAudioEngine` + `SFSpeechRecognizer`
    - [x] Implement permission request/authorization flow
    - [x] Enforce `requiresOnDeviceRecognition` and handle unsupported locales/devices
    - [x] Expose async start/stop APIs returning final transcript or errors
- [x] Error and state handling
    - [x] Surface inline messaging for permission denial, recognition failure, and short utterances
    - [x] Integrate `AppLogger` events for recording lifecycle and failures
    - [x] Reset UI state after send to re-enable the microphone bar
- [ ] Testing
    - [ ] Add unit tests for `SpeechRecognitionService` behavior (success, failure, permission denied)
    - [ ] Update chat flow tests to cover transcript-driven sends
    - [ ] Extend UI automation to simulate long-press mic interaction with mocked speech results
- [ ] Documentation & tooling
    - [ ] Refresh simulator smoke test instructions to cover microphone workflow
    - [ ] Note localization follow-ups and design cues (haptics/sounds) for future iterations

## Open Questions & Follow-ups
- Should we display the recognized transcript before sending (allowing cancel/edit)? Could be v2 scope.
- Do we need haptics/sound cues while recording? align with design once assets/haptics specs exist.
- Determine localization requirements for permission prompts and inline errors.

Novel Editor

A native macOS app for writing novels and long-form fiction with an AI assistant that actually understands your story.

Novel Editor is a distraction-free writing environment for authors who work with scenes. Structure your novel as a collection of scenes, drag them into the right order, and let an AI assistant help you develop dialogue, deepen characters, and smooth transitions — all without leaving your manuscript.

Features:

1). Scene-Based Writing

Break your novel into scenes and chapters
Drag-and-drop reordering in the sidebar
Each scene is an independent block — write in any order, rearrange later
Auto-save and project persistence in JSON

2). AI Assistant Built In

Chat panel integrated directly below the editor
Context-aware mode — toggle a checkbox to send the current scene as context, so the AI knows what you're working on
Ask for help with:

Dialogue polishing
Character development
Scene descriptions
Plot suggestions
Rephrasing and synonyms

3). Scene Interpolation

Select two adjacent scenes and merge them into one seamless flow
AI rewrites the ending of the first scene and the beginning of the second so they blend naturally
No awkward transitions, no repeated information

4). One-Click Browser Authentication

Connect to OpenRouter through your browser via OAuth PKCE
No API keys to copy-paste, no setup wizards
After authorization, the app runs a test request and shows a green indicator when everything works

5). Free Models Out of the Box

Through OpenRouter, you get instant access to powerful free models:

DeepSeek R1 — reasoning model for complex plotting
DeepSeek V3 — fast and capable for everyday writing
Gemini 2.0 Flash — great for brainstorming
Llama 3.3 70B — solid all-rounder
Qwen 2.5 72B — strong multilingual support
Switch models with a dropdown above the chat — no restart needed.

6). Works Fully Offline

Every core feature works without an internet connection:

Writing, editing, reordering scenes
Saving and loading projects
Export
AI features activate only when you're connected.

7). Requirements

macOS 14.0 (Sonoma) or later
Xcode 15.0+ (only for building from source)
An OpenRouter account (free) for AI features

8). Installation

From Source

bash
git clone https://github.com/yourusername/novel-editor.git
cd novel-editor
open NovelEditor.xcodeproj
Then press ⌘+R in Xcode.

Enabling AI

Open the app
Go to AI → Connection
Click Connect via Browser
Authorize in your browser — the app will handle the rest
Pick a model from the dropdown above the chat

Tip: All models listed in the app are free tier on OpenRouter. You can write for hours without spending a cent.

Architecture

Layer	Technology
UI	SwiftUI
Text Editing	NSTextView (AppKit)
State	MVVM + Combine
Persistence	JSON + FileManager
Secure Storage	Keychain
OAuth	ASWebAuthenticationSession + PKCE
AI Providers	OpenRouter (OpenAI-compatible API)
Networking	URLSession + SSE streaming
text
NovelEditor/
├── Models/          # Block, Project, ChatMessage, AIModel
├── ViewModels/      # ProjectViewModel, ChatViewModel
├── Views/           # Sidebar, Editor, ChatPanel, ConnectionView
├── Services/        # AIClient, OpenRouterAuth, KeychainStore
└── App/             # Entry point

Roadmap

☑ Scene-based text editor
☑ Drag-and-drop scene reordering
☑ Browser-based OAuth for OpenRouter
☑ Free model support (DeepSeek, Gemini, Llama, Qwen)
☑ Context-aware chat with toggle
☑ Scene interpolation
☑ Rephrase / synonyms
□ Export to EPUB, PDF, DOCX
□ Character and location database
□ Plot outline view
□ Version history with diff
□ Local AI models (MLX, Ollama)
□ Direct integrations (Anthropic, OpenAI, Gemini)
□ Cloud sync

Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

bash
git checkout -b feature/your-feature
git commit -m "Add your feature"
git push origin feature/your-feature

License

MIT License — see LICENSE for details.

Acknowledgments

OpenRouter — unified API for free and paid models
Swifter — lightweight HTTP server for OAuth callback
Apple's SwiftUI, AppKit, and Network frameworks
Built for writers who want a quiet place to work — with a thoughtful assistant nearby.
Built for writers who want a quiet place to work — with a thoughtful assistant nearby.

⭐ If you find this useful, consider starring the repo. It helps others discover the project.

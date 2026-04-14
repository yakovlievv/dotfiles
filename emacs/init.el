;;; init.el -*- lexical-binding: t; -*-

(doom! :input

       :completion
       (corfu +orderless)  ; complete with cap(f), cape and a flying feather!
       vertico           ; the search engine of the future

       :ui
       doom              ; what makes DOOM look the way it does
       doom-dashboard    ; a nifty splash screen for Emacs
       ligatures
       hl-todo           ; highlight TODO/FIXME/NOTE/DEPRECATED/HACK/REVIEW
       modeline          ; snazzy, Atom-inspired modeline, plus API
       nav-flash
       ophints           ; highlight the region an operation acts on
       (popup +defaults)   ; tame sudden yet inevitable temporary windows
       (vc-gutter +pretty) ; vcs diff in the fringe
       vi-tilde-fringe   ; fringe tildes to mark beyond EOB
       window-select
       workspaces        ; tab emulation, persistence & separate workspaces
       zen

       :editor
       (evil +everywhere); come to the dark side, we have cookies
       file-templates    ; auto-snippets for empty files
       snippets          ; yasnippet support
       fold              ; (nigh) universal code folding
       (whitespace +guess +trim)  ; a butler for your whitespace
       word-wrap

       :emacs
       dired             ; making dired pretty [functional]
       electric          ; smarter, keyword-based electric-indent
       ibuffer
       tramp             ; remote files at your arthritic fingertips
       undo              ; persistent, smarter undo for your inevitable mistakes
       vc                ; version-control and Emacs, sitting in a tree

       :term

       :checkers
       syntax              ; tasing you for every semicolon you forget
       (spell +aspell)
       grammar

       :tools
       (eval +overlay)     ; run code, run (also, repls)
       lookup              ; navigate your code and its documentation
       magit             ; a git porcelain for Emacs
       pdf

       :os
       (:if (featurep :system 'macos) macos)  ; improve compatibility with macOS

       :lang
       (org +roam2 +agenda +habits +pretty +pandoc)
       emacs-lisp        ; drown in parentheses
       markdown          ; writing docs for people to ignore
       sh                ; she sells {ba,z,fi}sh shells on the C xor

       :email

       :app
       calendar

       :config
       (default +bindings +smartparens))

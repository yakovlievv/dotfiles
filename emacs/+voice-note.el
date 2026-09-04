;;; +voice-note.el --- Voice notes attached to org entries -*- lexical-binding: t; -*-

;; Record a voice memo, attach it to the org entry at point, and
;; optionally insert a whisper transcript underneath it.
;;
;; The recording is written straight to `voice-note-directory' (a folder
;; kept outside the vault's git history and symlinked in, the same way
;; `material' is) and attached with the `lnk' method, so org-attach sees
;; a symlink while the audio itself never enters the repo.

(require 'org)
(require 'org-attach)
(require 'cl-lib)

;;; Customization

(defgroup voice-note nil
  "Record voice notes into org attachments."
  :group 'org)

(defcustom voice-note-directory "~/org/audio"
  "Directory recordings are written to.
Kept out of the vault's git history; org-attach only stores a symlink."
  :type 'directory :group 'voice-note)

(defcustom voice-note-ffmpeg-executable "ffmpeg"
  "Path to the ffmpeg binary used for capture."
  :type 'string :group 'voice-note)

(defcustom voice-note-input-device ":MacBook Air Microphone"
  "AVFoundation input spec, as \"VIDEO:AUDIO\".
Prefer a device *name* over an index: indices shift around when an
iPhone continuity microphone appears or disappears.  List the available
devices with

  ffmpeg -f avfoundation -list_devices true -i \"\""
  :type 'string :group 'voice-note)

(defcustom voice-note-ffmpeg-args
  '("-ac" "1" "-ar" "44100" "-c:a" "libmp3lame" "-b:a" "64k")
  "Encoding arguments passed to ffmpeg.
Mono MP3 keeps files around 480 KB/minute and is one of the few formats
whisper.cpp reads directly (flac, mp3, ogg, wav — notably not m4a), so
nothing has to be converted before transcription."
  :type '(repeat string) :group 'voice-note)

(defcustom voice-note-file-extension "mp3"
  "Extension matching `voice-note-ffmpeg-args'."
  :type 'string :group 'voice-note)

(defcustom voice-note-attach-method 'lnk
  "Method passed to `org-attach-attach'.
`lnk' symlinks the recording into the attachment directory and leaves
the audio itself in `voice-note-directory'.  `cp' or `mv' copy or move
the bytes into `.attach', which puts them under version control."
  :type '(choice (const :tag "Symlink" lnk)
                 (const :tag "Copy" cp)
                 (const :tag "Move" mv))
  :group 'voice-note)

(defcustom voice-note-minimum-size 2000
  "Recordings smaller than this many bytes are treated as misfires."
  :type 'integer :group 'voice-note)

;;;; Transcription

(defcustom voice-note-transcribe t
  "Whether to transcribe automatically after a recording is attached."
  :type 'boolean :group 'voice-note)

(defcustom voice-note-whisper-executable "whisper-cli"
  "Path to the whisper.cpp CLI."
  :type 'string :group 'voice-note)

(defcustom voice-note-whisper-model
  (expand-file-name "~/.local/share/whisper-cpp/models/ggml-large-v3-turbo.bin")
  "Path to the ggml whisper model.
Homebrew's whisper-cpp ships binaries only; models are downloaded
separately from https://huggingface.co/ggerganov/whisper.cpp."
  :type 'file :group 'voice-note)

(defcustom voice-note-whisper-language "auto"
  "Spoken language, or \"auto\" to detect per recording."
  :type 'string :group 'voice-note)

(defcustom voice-note-whisper-extra-args nil
  "Additional arguments for whisper-cli."
  :type '(repeat string) :group 'voice-note)

(defcustom voice-note-transcript-heading "Transcript"
  "Heading text for the inserted transcript."
  :type 'string :group 'voice-note)

;;;; Playback

(defcustom voice-note-player-executable "afplay"
  "Command used to play a recording back."
  :type 'string :group 'voice-note)

(defcustom voice-note-playback-rate 1.0
  "Playback speed.  afplay accepts 0.4 to 3.0."
  :type 'number :group 'voice-note)

;;; State

(defvar voice-note--process nil)
(defvar voice-note--file nil)
(defvar voice-note--marker nil
  "Where the recording will be attached.
Captured when recording *starts*, so wandering off mid-thought is safe.")
(defvar voice-note--start-time nil)
(defvar voice-note--timer nil)
(defvar voice-note--play-process nil)

(defun voice-note-recording-p ()
  (process-live-p voice-note--process))

;;; Mode line

(defun voice-note--mode-line ()
  (when (voice-note-recording-p)
    (let ((secs (floor (float-time (time-since voice-note--start-time)))))
      (propertize (format " ●REC %d:%02d " (/ secs 60) (mod secs 60))
                  'face 'error))))

(defun voice-note--mode-line-setup ()
  (unless (memq 'voice-note--mode-line-entry global-mode-string)
    (setq global-mode-string
          (append global-mode-string '((:eval (voice-note--mode-line))))))
  (setq voice-note--timer
        (run-with-timer 1 1 (lambda () (force-mode-line-update t)))))

(defun voice-note--mode-line-teardown ()
  (when (timerp voice-note--timer)
    (cancel-timer voice-note--timer))
  (setq voice-note--timer nil)
  (force-mode-line-update t))

;;; Recording

(defun voice-note--slug (s)
  (let ((s (downcase (or s ""))))
    (setq s (replace-regexp-in-string "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" s))
    (setq s (replace-regexp-in-string "[^[:alnum:]]+" "-" s))
    (setq s (string-trim s "-+" "-+"))
    (if (> (length s) 40) (substring s 0 40) s)))

(defun voice-note--new-file ()
  (let* ((dir (expand-file-name voice-note-directory))
         (slug (voice-note--slug (org-get-heading t t t t)))
         (stamp (format-time-string "%Y%m%dT%H%M%S")))
    (make-directory dir t)
    (expand-file-name
     (concat stamp (unless (string-empty-p slug) (concat "--" slug))
             "." voice-note-file-extension)
     dir)))

;;;###autoload
(defun voice-note-start ()
  "Start recording a voice note for the org entry at point."
  (interactive)
  (when (voice-note-recording-p)
    (user-error "Already recording"))
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an org buffer"))
  (unless (org-at-heading-p) (org-back-to-heading t))
  (setq voice-note--file (voice-note--new-file)
        voice-note--marker (point-marker)
        voice-note--start-time (current-time))
  (setq voice-note--process
        (make-process
         :name "voice-note-record"
         :buffer (get-buffer-create " *voice-note-record*")
         :connection-type 'pipe
         :noquery t
         :command (append (list voice-note-ffmpeg-executable
                                "-hide_banner" "-loglevel" "error" "-nostdin"
                                "-f" "avfoundation" "-i" voice-note-input-device)
                          voice-note-ffmpeg-args
                          (list "-y" voice-note--file))
         :sentinel #'voice-note--record-sentinel))
  (voice-note--mode-line-setup)
  (message "Recording — same binding again to stop"))

;;;###autoload
(defun voice-note-stop ()
  "Stop recording and attach the result."
  (interactive)
  (unless (voice-note-recording-p) (user-error "Not recording"))
  ;; SIGINT rather than SIGKILL: ffmpeg needs to finalise the file.
  (interrupt-process voice-note--process)
  (message "Finishing recording..."))

;;;###autoload
(defun voice-note-toggle ()
  "Start recording, or stop and attach if already recording."
  (interactive)
  (if (voice-note-recording-p) (voice-note-stop) (voice-note-start)))

;;;###autoload
(defun voice-note-cancel ()
  "Abort the current recording and delete the file."
  (interactive)
  (unless (voice-note-recording-p) (user-error "Not recording"))
  (let ((file voice-note--file))
    (setq voice-note--file nil)          ; tells the sentinel to stay out
    (kill-process voice-note--process)
    (run-at-time 0.5 nil (lambda ()
                           (when (file-exists-p file) (delete-file file))
                           (message "Recording discarded")))))

(defun voice-note--record-sentinel (_proc event)
  (unless (string-match-p "\\`\\(run\\|open\\)" event)
    (voice-note--mode-line-teardown)
    (let ((file voice-note--file)
          (marker voice-note--marker))
      (setq voice-note--process nil)
      ;; ffmpeg exits non-zero on SIGINT, so judge by the file, not the code.
      (cond
       ((null file) nil)                 ; cancelled
       ((not (file-exists-p file))
        (message "Voice note: ffmpeg produced no file — check `voice-note-input-device'"))
       ((< (file-attribute-size (file-attributes file)) voice-note-minimum-size)
        (delete-file file)
        (message "Voice note: recording too short, discarded"))
       ((not (buffer-live-p (marker-buffer marker)))
        (message "Voice note: buffer gone, recording kept at %s" file))
       (t
        (org-with-point-at marker
          (org-attach-attach file nil voice-note-attach-method))
        (message "Attached %s" (file-name-nondirectory file))
        (when voice-note-transcribe
          (voice-note--transcribe file marker)))))))

;;; Transcription

(defun voice-note--transcribe (file marker)
  (cond
   ((not (executable-find voice-note-whisper-executable))
    (message "Voice note: %s not found; attached without transcript"
             voice-note-whisper-executable))
   ((not (file-exists-p voice-note-whisper-model))
    (message "Voice note: whisper model missing at %s" voice-note-whisper-model))
   (t
    (let ((base (make-temp-file "voice-note-")))
      (message "Transcribing %s..." (file-name-nondirectory file))
      (make-process
       :name "voice-note-whisper"
       :buffer (get-buffer-create " *voice-note-whisper*")
       :noquery t
       :command (append (list voice-note-whisper-executable
                              "-m" (expand-file-name voice-note-whisper-model)
                              "-f" (expand-file-name file)
                              "-l" voice-note-whisper-language
                              "-np" "-nt" "-otxt" "-of" base)
                        voice-note-whisper-extra-args)
       :sentinel
       (lambda (_p event)
         (unless (string-match-p "\\`\\(run\\|open\\)" event)
           (let ((txt (concat base ".txt")))
             (if (not (file-exists-p txt))
                 (message "Voice note: transcription failed (see ' *voice-note-whisper*')")
               (let ((text (voice-note--read-transcript txt)))
                 (delete-file txt)
                 (if (string-empty-p text)
                     (message "Voice note: transcript came back empty")
                   (voice-note--insert-transcript marker text)
                   (message "Transcript inserted")))))
           (when (file-exists-p base) (delete-file base)))))))))

(defun voice-note--read-transcript (txt)
  (with-temp-buffer
    (insert-file-contents txt)
    (string-trim
     (mapconcat #'string-trim
                (split-string (buffer-string) "\n" t "[ \t]+")
                " "))))

(defun voice-note--insert-transcript (marker text)
  (if (not (buffer-live-p (marker-buffer marker)))
      (message "Voice note: buffer gone, transcript dropped")
    (org-with-point-at marker
      (org-back-to-heading t)
      (let ((level (org-current-level)))
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n"))
        (insert (make-string (1+ level) ?*) " " voice-note-transcript-heading "\n"
                text "\n")))))

;;;###autoload
(defun voice-note-transcribe-attachment ()
  "Transcribe an existing audio attachment of the entry at point."
  (interactive)
  (voice-note--transcribe (voice-note--pick-attachment) (point-marker)))

;;; Playback

(defun voice-note--audio-attachments ()
  (let ((dir (org-attach-dir)))
    (when dir
      (cl-remove-if-not
       (lambda (f) (string-match-p "\\.\\(mp3\\|m4a\\|wav\\|flac\\|ogg\\|opus\\)\\'" f))
       (org-attach-file-list dir)))))

(defun voice-note--pick-attachment ()
  (let* ((dir (or (org-attach-dir) (user-error "No attachments here")))
         (files (or (voice-note--audio-attachments)
                    (user-error "No audio attached to this entry"))))
    (expand-file-name
     (if (cdr files) (completing-read "Play: " files nil t) (car files))
     dir)))

;;;###autoload
(defun voice-note-play ()
  "Play an audio attachment of the entry at point, or stop playback."
  (interactive)
  (if (process-live-p voice-note--play-process)
      (progn (kill-process voice-note--play-process)
             (setq voice-note--play-process nil)
             (message "Playback stopped"))
    (let ((file (voice-note--pick-attachment)))
      (setq voice-note--play-process
            (make-process
             :name "voice-note-play"
             :buffer (get-buffer-create " *voice-note-play*")
             :noquery t
             :command (list voice-note-player-executable
                            "--rate" (number-to-string voice-note-playback-rate)
                            file)))
      (message "Playing %s%s" (file-name-nondirectory file)
               (if (= voice-note-playback-rate 1.0) ""
                 (format " at %sx" voice-note-playback-rate))))))

;;; Keybindings

;; NOTE: `SPC n v' is Doom's `org-search-view', so it cannot double as a
;; prefix -- hence capital V.  Free keys under `SPC n' are scarce: Doom
;; claims most lowercase ones, `n b' is the book gallery and `n j' the
;; journal prefix.
(map! :leader
      (:prefix ("n V" . "voice note")
       :desc "Record / stop"        "v" #'voice-note-toggle
       :desc "Play / stop"          "p" #'voice-note-play
       :desc "Cancel recording"     "c" #'voice-note-cancel
       :desc "Transcribe attachment" "t" #'voice-note-transcribe-attachment))

(provide '+voice-note)
;;; +voice-note.el ends here

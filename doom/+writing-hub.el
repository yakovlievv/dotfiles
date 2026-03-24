;;; +writing-hub.el --- Daily writing stats for org-roam -*- lexical-binding: t; -*-

;;; State

(defvar writing-hub--org-dir (expand-file-name "~/org/"))
(defvar writing-hub--roam-dir (expand-file-name "~/org/roam/"))
(defvar writing-hub--baseline-in-progress nil
  "Guard flag to prevent concurrent baseline commits.")
(defvar writing-hub--baseline-confirmed-date nil
  "Date string for which baseline has been confirmed to exist.
Avoids repeated git log calls on every focus event.")
(defvar writing-hub--view 'today
  "Current view mode: `today' or `week'.")
(defvar writing-hub--day-offset 0
  "Day offset from today.  0 = today, -1 = yesterday, etc.")

;;; Baseline commit

(defun writing-hub--today-date-string ()
  "Return today's date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"))

(defun writing-hub--today-prefix ()
  "Return today's date as YYYYMMDD for matching org-roam filenames."
  (format-time-string "%Y%m%d"))

(defun writing-hub--viewed-time ()
  "Return the time object for the currently viewed day."
  (let ((now (decode-time)))
    (encode-time 0 0 0
                 (+ (nth 3 now) writing-hub--day-offset)
                 (nth 4 now) (nth 5 now))))

(defun writing-hub--viewed-date-string ()
  "Return the viewed day's date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d" (writing-hub--viewed-time)))

(defun writing-hub--viewed-prefix ()
  "Return the viewed day's date as YYYYMMDD."
  (format-time-string "%Y%m%d" (writing-hub--viewed-time)))

(defun writing-hub--baseline-message ()
  "Return the baseline commit message for today."
  (format "daily-baseline: %s" (writing-hub--today-date-string)))

(defun writing-hub--baseline-exists-p ()
  "Check if a baseline commit exists for today."
  (let ((default-directory writing-hub--org-dir))
    (not (string-empty-p
          (string-trim
           (shell-command-to-string
            (format "git log --oneline --grep='daily-baseline: %s' --since='%s 00:00' 2>/dev/null"
                    (writing-hub--today-date-string)
                    (writing-hub--today-date-string))))))))

(defun writing-hub--baseline-sha ()
  "Return the SHA of today's baseline commit, or nil."
  (let ((default-directory writing-hub--org-dir))
    (let ((sha (string-trim
                (shell-command-to-string
                 (format "git log --format='%%H' --grep='daily-baseline: %s' --since='%s 00:00' -1 2>/dev/null"
                         (writing-hub--today-date-string)
                         (writing-hub--today-date-string))))))
      (unless (string-empty-p sha) sha))))

(defun writing-hub--create-baseline ()
  "Create the daily baseline commit and push.
Only stages files under roam/. Skips commit if nothing to stage."
  (let ((default-directory writing-hub--org-dir))
    (shell-command "git add -- roam/")
    (if (string-empty-p
         (string-trim (shell-command-to-string "git diff --cached --name-only")))
        ;; Nothing staged — use the current HEAD as the baseline.
        ;; Tag it so we can find it with --grep.
        (shell-command
         (format "git commit --allow-empty -m %s"
                 (shell-quote-argument (writing-hub--baseline-message))))
      (shell-command
       (format "git commit -m %s"
               (shell-quote-argument (writing-hub--baseline-message)))))
    (start-process "org-baseline-push" nil "git" "push")))

(defun writing-hub--ensure-baseline ()
  "Create today's baseline commit if it doesn't exist yet.
Caches the result per day to avoid repeated git log calls."
  (let ((today (writing-hub--today-date-string)))
    (when (and (not writing-hub--baseline-in-progress)
               (not (equal writing-hub--baseline-confirmed-date today))
               (file-directory-p writing-hub--org-dir)
               (file-directory-p (concat writing-hub--org-dir ".git")))
      (if (writing-hub--baseline-exists-p)
          (setq writing-hub--baseline-confirmed-date today)
        (setq writing-hub--baseline-in-progress t)
        (unwind-protect
            (progn
              (writing-hub--create-baseline)
              (setq writing-hub--baseline-confirmed-date today))
          (setq writing-hub--baseline-in-progress nil))))))

(defun writing-hub--on-focus ()
  "Focus change handler — ensure baseline exists when Emacs gains focus."
  (when (frame-focus-state)
    (writing-hub--ensure-baseline)))

;; Register hooks
(add-function :after after-focus-change-function #'writing-hub--on-focus)

;; Midnight timer: schedule for next midnight, repeat daily
(let* ((now (decode-time))
       (tomorrow-midnight (encode-time 0 0 0
                                       (1+ (nth 3 now))
                                       (nth 4 now)
                                       (nth 5 now)))
       (seconds-until (float-time (time-subtract tomorrow-midnight (current-time)))))
  (run-with-timer seconds-until 86400 #'writing-hub--ensure-baseline))

;;; Week helpers

(defun writing-hub--week-start ()
  "Return timestamp for Monday 00:00 of the current week."
  (let* ((now (decode-time))
         (dow (nth 6 now))
         (days-since-mon (if (= dow 0) 6 (1- dow))))
    (encode-time 0 0 0
                 (- (nth 3 now) days-since-mon)
                 (nth 4 now) (nth 5 now))))

(defun writing-hub--week-date-prefixes ()
  "Return list of YYYYMMDD prefixes for each day from Monday to today."
  (let* ((now (decode-time))
         (dow (nth 6 now))
         (days-since-mon (if (= dow 0) 6 (1- dow)))
         prefixes)
    (dotimes (i (1+ days-since-mon))
      (let ((day-time (encode-time 0 0 0
                                   (- (nth 3 now) (- days-since-mon i))
                                   (nth 4 now) (nth 5 now))))
        (push (format-time-string "%Y%m%d" day-time) prefixes)))
    (nreverse prefixes)))

(defun writing-hub--week-baseline-sha ()
  "Return SHA for the weekly diff baseline.
Tries the earliest daily-baseline commit this week (Monday's).
Falls back to the most recent commit before Monday."
  (let ((default-directory writing-hub--org-dir))
    (let* ((monday (writing-hub--week-start))
           (since-str (format-time-string "%Y-%m-%d" monday))
           ;; Try: earliest baseline this week
           (sha (string-trim
                 (shell-command-to-string
                  (format "git log --format='%%H' --grep='daily-baseline:' --since='%s' --reverse -1 2>/dev/null"
                          since-str)))))
      (when (string-empty-p sha)
        ;; Fallback: most recent commit before Monday
        (setq sha (string-trim
                   (shell-command-to-string
                    (format "git log --format='%%H' --until='%s' -1 2>/dev/null"
                            since-str)))))
      (unless (string-empty-p sha) sha))))

;;; Day-offset helpers

(defun writing-hub--date-baseline-sha (date-str)
  "Return the SHA of the baseline commit for DATE-STR (YYYY-MM-DD), or nil."
  (let ((default-directory writing-hub--org-dir))
    (let ((sha (string-trim
                (shell-command-to-string
                 (format "git log --format='%%H' --grep='daily-baseline: %s' --since='%s 00:00' --until='%s 23:59' -1 2>/dev/null"
                         date-str date-str date-str)))))
      (unless (string-empty-p sha) sha))))

(defun writing-hub--next-day-string (date-str)
  "Return the day after DATE-STR as YYYY-MM-DD."
  (let* ((parsed (parse-time-string (concat date-str " 00:00:00")))
         (time (encode-time 0 0 0 (1+ (nth 3 parsed)) (nth 4 parsed) (nth 5 parsed))))
    (format-time-string "%Y-%m-%d" time)))

(defun writing-hub--date-end-sha (date-str)
  "Return the SHA representing the end-of-day state for DATE-STR.
For today, returns nil (meaning diff against working tree).
For past days, returns the next day's baseline, or the last commit before next day."
  (if (string= date-str (writing-hub--today-date-string))
      nil
    (let* ((default-directory writing-hub--org-dir)
           (next-day (writing-hub--next-day-string date-str))
           ;; Try next day's baseline first
           (sha (writing-hub--date-baseline-sha next-day)))
      (unless sha
        ;; Fallback: last commit before next day midnight
        (setq sha (string-trim
                   (shell-command-to-string
                    (format "git log --format='%%H' --until='%s 00:00' -1 2>/dev/null"
                            next-day)))))
      (unless (string-empty-p sha) sha))))

(defun writing-hub--files-created-on-date (prefix)
  "Return list of org-roam files whose name starts with PREFIX."
  (let ((files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (string-prefix-p prefix (file-name-nondirectory f)))
                files)))

(defun writing-hub--per-file-words-range (start-sha end-sha created-files)
  "Parse git diff from START-SHA to END-SHA and return per-file word counts.
END-SHA nil means diff against working tree."
  (let ((default-directory writing-hub--org-dir)
        (result (make-hash-table :test 'equal))
        current-file file-added file-deleted)
    (when start-sha
      (let* ((range (if end-sha
                        (format "%s..%s" start-sha end-sha)
                      start-sha))
             (diff-output (shell-command-to-string
                           (format "git -c core.quotepath=false diff %s -- roam/ 2>/dev/null" range))))
        (dolist (line (split-string diff-output "\n"))
          (cond
           ((string-prefix-p "+++ b/" line)
            (when current-file
              (puthash current-file
                       (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                             (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                       result))
            (setq current-file (expand-file-name (substring line 6) writing-hub--org-dir)
                  file-added 0
                  file-deleted 0))
           ;; Skip deleted files (+++ /dev/null)
           ((string-prefix-p "+++ " line)
            (when current-file
              (puthash current-file
                       (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                             (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                       result))
            (setq current-file nil))
           ((and current-file
                 (string-prefix-p "+" line)
                 (not (string-prefix-p "+++" line)))
            (let ((content (substring line 1)))
              (unless (writing-hub--metadata-line-p content)
                (setq file-added (+ file-added (writing-hub--count-line-words content))))))
           ((and current-file
                 (string-prefix-p "-" line)
                 (not (string-prefix-p "---" line)))
            (let ((content (substring line 1)))
              (unless (writing-hub--metadata-line-p content)
                (setq file-deleted (+ file-deleted (writing-hub--count-line-words content))))))))
        (when current-file
          (puthash current-file
                   (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                         (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                   result))
        ;; Created files not already in the diff (untracked at baseline time)
        (dolist (file created-files)
          (unless (gethash file result)
            (let ((words (if end-sha
                             ;; Past day: read file content from end-of-day commit
                             (writing-hub--count-file-words-at-rev file end-sha)
                           ;; Today: read from disk
                           (if (file-exists-p file)
                               (writing-hub--count-file-words file)
                             0))))
              (when (> words 0)
                (puthash file (cons words 0) result)))))))
    result))

(defun writing-hub--files-deleted-range (start-sha end-sha)
  "Return list of roam files deleted between START-SHA and END-SHA."
  (let ((default-directory writing-hub--org-dir))
    (when start-sha
      (let* ((range (if end-sha
                        (format "%s..%s" start-sha end-sha)
                      start-sha))
             (output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=D %s -- roam/ 2>/dev/null" range))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n"))))
        (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))))

(defun writing-hub--files-modified-on-date (date-str prefix start-sha end-sha)
  "Return files modified on DATE-STR (not created), using git diff."
  (let ((default-directory writing-hub--org-dir)
        (created (writing-hub--files-created-on-date prefix)))
    (when start-sha
      (let* ((range (if end-sha
                        (format "%s..%s" start-sha end-sha)
                      start-sha))
             (output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=M %s -- roam/ 2>/dev/null" range))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n")))
             (abs-files (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))
        (seq-filter (lambda (f) (not (member f created))) abs-files)))))

;;; Data layer

(defun writing-hub--file-title (file)
  "Extract #+title: from FILE, or return the file base name."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 500)
        (if (re-search-forward "^#\\+title:\\s-*\\(.*\\)" nil t)
            (match-string 1)
          (file-name-base file)))
    (error (file-name-base file))))

(defun writing-hub--files-created-today ()
  "Return list of org-roam files created today (by filename prefix)."
  (let ((prefix (writing-hub--today-prefix))
        (files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (string-prefix-p prefix (file-name-nondirectory f)))
                files)))

(defun writing-hub--today-start ()
  "Return timestamp for today 00:00."
  (let ((now (decode-time)))
    (encode-time 0 0 0 (nth 3 now) (nth 4 now) (nth 5 now))))

(defun writing-hub--files-modified-today ()
  "Return list of org-roam files modified today, excluding those created today."
  (let* ((today (writing-hub--today-start))
         (created (writing-hub--files-created-today))
         (all-files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (and (not (member f created))
                       (let ((mtime (file-attribute-modification-time
                                     (file-attributes f))))
                         (and mtime (time-less-p today mtime)))))
                all-files)))

(defun writing-hub--files-created-this-week ()
  "Return list of org-roam files created this week (by filename prefix)."
  (let ((prefixes (writing-hub--week-date-prefixes))
        (files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (let ((name (file-name-nondirectory f)))
                    (seq-some (lambda (p) (string-prefix-p p name)) prefixes)))
                files)))

(defun writing-hub--files-modified-this-week ()
  "Return list of org-roam files modified this week, excluding those created this week."
  (let* ((week-start (writing-hub--week-start))
         (created (writing-hub--files-created-this-week))
         (all-files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (and (not (member f created))
                       (let ((mtime (file-attribute-modification-time
                                     (file-attributes f))))
                         (and mtime (time-less-p week-start mtime)))))
                all-files)))

(defun writing-hub--words-this-week ()
  "Return per-file word counts for this week as a hash table."
  (writing-hub--per-file-words
   (writing-hub--week-baseline-sha)
   (writing-hub--files-created-this-week)))

(defun writing-hub--files-deleted-this-week ()
  "Return list of roam files deleted since the week's baseline."
  (let ((sha (writing-hub--week-baseline-sha))
        (default-directory writing-hub--org-dir))
    (when sha
      (let* ((output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=D %s -- roam/ 2>/dev/null" sha))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n"))))
        (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))))

;;; View-aware dispatch

(defun writing-hub--get-created ()
  (cond
   ((eq writing-hub--view 'week)
    (writing-hub--files-created-this-week))
   ((= writing-hub--day-offset 0)
    (writing-hub--files-created-today))
   (t (writing-hub--files-created-on-date (writing-hub--viewed-prefix)))))

(defun writing-hub--get-modified ()
  (cond
   ((eq writing-hub--view 'week)
    (writing-hub--files-modified-this-week))
   ((= writing-hub--day-offset 0)
    (writing-hub--files-modified-today))
   (t (let* ((date-str (writing-hub--viewed-date-string))
             (prefix (writing-hub--viewed-prefix))
             (start (writing-hub--date-baseline-sha date-str))
             (end (writing-hub--date-end-sha date-str)))
        (writing-hub--files-modified-on-date date-str prefix start end)))))

(defun writing-hub--get-deleted ()
  (cond
   ((eq writing-hub--view 'week)
    (writing-hub--files-deleted-this-week))
   ((= writing-hub--day-offset 0)
    (writing-hub--files-deleted-today))
   (t (let* ((date-str (writing-hub--viewed-date-string))
             (start (writing-hub--date-baseline-sha date-str))
             (end (writing-hub--date-end-sha date-str)))
        (writing-hub--files-deleted-range start end)))))

(defun writing-hub--get-words ()
  (cond
   ((eq writing-hub--view 'week)
    (writing-hub--words-this-week))
   ((= writing-hub--day-offset 0)
    (writing-hub--words-today))
   (t (let* ((date-str (writing-hub--viewed-date-string))
             (prefix (writing-hub--viewed-prefix))
             (start (writing-hub--date-baseline-sha date-str))
             (end (writing-hub--date-end-sha date-str))
             (created (writing-hub--files-created-on-date prefix)))
        (writing-hub--per-file-words-range start end created)))))

(defun writing-hub--view-label ()
  (cond
   ((eq writing-hub--view 'week) "This Week")
   ((= writing-hub--day-offset 0) "Today")
   ((= writing-hub--day-offset -1) "Yesterday")
   (t (format-time-string "%A, %b %d" (writing-hub--viewed-time)))))

(defun writing-hub--metadata-line-p (line)
  "Return non-nil if LINE is org metadata (#+keyword, property drawer, etc)."
  (let ((trimmed (string-trim-left line)))
    (or (string-prefix-p "#+" trimmed)
        (string-prefix-p ":" trimmed)
        (string-match-p "^\\(CLOCK:\\|DEADLINE:\\|SCHEDULED:\\|CLOSED:\\)" trimmed))))

(defun writing-hub--strip-org-links (line)
  "Strip org links from LINE, keeping only descriptions.
[[target][description]] → description, [[target]] → removed."
  (let ((result line))
    ;; First: [[target][description]] → description
    (setq result (replace-regexp-in-string
                  "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" result))
    ;; Then: bare [[target]] → empty
    (setq result (replace-regexp-in-string
                  "\\[\\[[^]]*\\]\\]" "" result))
    result))

(defun writing-hub--count-line-words (line)
  "Count words in a single LINE after stripping org links."
  (length (split-string (writing-hub--strip-org-links line) nil t)))

(defun writing-hub--count-file-words (file)
  "Count total words in FILE, excluding metadata lines."
  (condition-case nil
      (let ((count 0))
        (with-temp-buffer
          (insert-file-contents file)
          (dolist (line (split-string (buffer-string) "\n"))
            (unless (writing-hub--metadata-line-p line)
              (setq count (+ count (writing-hub--count-line-words line))))))
        count)
    (error 0)))

(defun writing-hub--count-words-from-string (content)
  "Count words in CONTENT string, excluding metadata lines."
  (let ((count 0))
    (dolist (line (split-string content "\n"))
      (unless (writing-hub--metadata-line-p line)
        (setq count (+ count (writing-hub--count-line-words line)))))
    count))

(defun writing-hub--count-file-words-at-rev (file rev)
  "Count words in FILE at git revision REV.
Falls back to reading FILE on disk if REV lookup fails."
  (let* ((default-directory writing-hub--org-dir)
         (relative (file-relative-name file writing-hub--org-dir))
         (content (string-trim
                   (shell-command-to-string
                    (format "git show %s:%s 2>/dev/null"
                            (shell-quote-argument rev)
                            (shell-quote-argument relative))))))
    (if (not (string-empty-p content))
        (writing-hub--count-words-from-string content)
      ;; Fallback: read from disk if available
      (if (file-exists-p file)
          (writing-hub--count-file-words file)
        0))))

(defun writing-hub--per-file-words (sha created-files)
  "Parse git diff against SHA and return per-file word counts.
Returns a hash table: absolute-file-path → (added . deleted).
CREATED-FILES are untracked files whose full word count is added."
  (let ((default-directory writing-hub--org-dir)
        (result (make-hash-table :test 'equal))
        current-file file-added file-deleted)
    (when sha
      (let ((diff-output (shell-command-to-string
                          (format "git -c core.quotepath=false diff %s -- roam/ 2>/dev/null" sha))))
        (dolist (line (split-string diff-output "\n"))
          (cond
           ;; New file header: +++ b/roam/filename.org
           ((string-prefix-p "+++ b/" line)
            (when current-file
              (puthash current-file
                       (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                             (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                       result))
            (setq current-file (expand-file-name (substring line 6) writing-hub--org-dir)
                  file-added 0
                  file-deleted 0))
           ;; Skip deleted files (+++ /dev/null)
           ((string-prefix-p "+++ " line)
            (when current-file
              (puthash current-file
                       (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                             (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                       result))
            (setq current-file nil))
           ;; Added line
           ((and current-file
                 (string-prefix-p "+" line)
                 (not (string-prefix-p "+++" line)))
            (let ((content (substring line 1)))
              (unless (writing-hub--metadata-line-p content)
                (setq file-added (+ file-added (writing-hub--count-line-words content))))))
           ;; Removed line
           ((and current-file
                 (string-prefix-p "-" line)
                 (not (string-prefix-p "---" line)))
            (let ((content (substring line 1)))
              (unless (writing-hub--metadata-line-p content)
                (setq file-deleted (+ file-deleted (writing-hub--count-line-words content)))))))))
      ;; Save last file
      (when current-file
        (puthash current-file
                 (cons (+ (car (gethash current-file result '(0 . 0))) file-added)
                       (+ (cdr (gethash current-file result '(0 . 0))) file-deleted))
                 result))
      ;; Created files not already in the diff (untracked at baseline time)
      (dolist (file created-files)
        (unless (gethash file result)
          (let ((words (if (file-exists-p file)
                           (writing-hub--count-file-words file)
                         0)))
            (when (> words 0)
              (puthash file (cons words 0) result))))))
    result))

(defun writing-hub--words-total (per-file-hash)
  "Sum all per-file word counts. Returns (total-added . total-deleted)."
  (let ((added 0) (deleted 0))
    (maphash (lambda (_file counts)
               (setq added (+ added (car counts))
                     deleted (+ deleted (cdr counts))))
             per-file-hash)
    (cons added deleted)))

(defun writing-hub--words-today ()
  "Return per-file word counts for today as a hash table."
  (writing-hub--per-file-words
   (writing-hub--baseline-sha)
   (writing-hub--files-created-today)))

(defun writing-hub--files-deleted-today ()
  "Return list of roam files deleted since baseline (tracked in baseline but gone)."
  (let ((sha (writing-hub--baseline-sha))
        (default-directory writing-hub--org-dir))
    (when sha
      (let* ((output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=D %s -- roam/ 2>/dev/null" sha))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n"))))
        (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))))

;;; Rendering

(defun writing-hub--file-title-from-git (file)
  "Extract #+title: from FILE's last git version, or return the file base name."
  (let* ((default-directory writing-hub--org-dir)
         (relative (file-relative-name file writing-hub--org-dir))
         (content (string-trim
                   (shell-command-to-string
                    (format "git show HEAD:%s 2>/dev/null"
                            (shell-quote-argument relative))))))
    (if (and (not (string-empty-p content))
             (string-match "^#\\+title:\\s-*\\(.*\\)" content))
        (match-string 1 content)
      (file-name-base file))))

(defun writing-hub--render ()
  "Render the writing hub buffer."
  (let* ((inhibit-read-only t)
         (view-label (writing-hub--view-label))
         (created (writing-hub--get-created))
         (per-file (writing-hub--get-words))
         (modified-raw (writing-hub--get-modified))
         (deleted-raw (writing-hub--get-deleted))
         ;; For today only: also detect deleted files not caught by git
         ;; (e.g. untracked files removed before commit).
         ;; For past days file-exists-p reflects NOW, not end-of-day, so skip.
         (deleted-from-diff
          (when (and (= writing-hub--day-offset 0)
                     (eq writing-hub--view 'today))
            (let (extra)
              (maphash (lambda (f _counts)
                         (when (and (not (file-exists-p f))
                                    (not (member f created))
                                    (not (member f deleted-raw)))
                           (push f extra)))
                       per-file)
              extra)))
         (deleted (append deleted-raw deleted-from-diff))
         ;; Modified: has word changes, not deleted, not created
         (modified (seq-filter (lambda (f)
                                 (and (not (member f deleted))
                                      (let ((counts (gethash f per-file '(0 . 0))))
                                        (or (> (car counts) 0) (> (cdr counts) 0)))))
                               modified-raw))
         (totals (writing-hub--words-total per-file))
         (words-added (car totals))
         (words-deleted (cdr totals)))
    (erase-buffer)
    ;; Header
    (insert (propertize (format "  Writing Hub — %s\n"
                                (format-time-string "%A, %B %d" (writing-hub--viewed-time)))
                        'face '(:weight bold :height 1.3)))
    (insert (propertize (format "  [%s]" view-label)
                        'face '(:foreground "#cba6f7" :weight bold)))
    (insert "\n\n")
    (insert (propertize (format "  +%d words" words-added)
                        'face '(:weight bold :foreground "#a6e3a1")))
    (insert "  ")
    (insert (propertize (format "-%d words" words-deleted)
                        'face '(:weight bold :foreground "#f38ba8")))
    (insert "  |  ")
    (insert (propertize (format "%d created" (length created))
                        'face '(:weight bold :foreground "#89b4fa")))
    (insert "  |  ")
    (insert (propertize (format "%d modified" (length modified))
                        'face '(:weight bold :foreground "#f9e2af")))
    (when deleted
      (insert "  |  ")
      (insert (propertize (format "%d deleted" (length deleted))
                          'face '(:weight bold :foreground "#f38ba8"))))
    (insert "\n\n")
    ;; Created section
    (when created
      (insert (propertize (format "  Created %s\n" view-label)
                          'face '(:weight bold :underline t)))
      (insert "\n")
      (dolist (f created)
        (let* ((title (writing-hub--file-title f))
               (counts (gethash f per-file '(0 . 0)))
               (fa (car counts))
               (fd (cdr counts)))
          (insert "  ")
          (insert (propertize title
                              'face '(:foreground "#89b4fa")
                              'writing-hub-file f
                              'mouse-face 'highlight))
          (when (> fa 0)
            (insert (propertize (format "  +%d" fa) 'face '(:foreground "#a6e3a1"))))
          (when (> fd 0)
            (insert (propertize (format "  -%d" fd) 'face '(:foreground "#f38ba8"))))
          (insert "\n")))
      (insert "\n"))
    ;; Modified section
    (when modified
      (insert (propertize (format "  Modified %s\n" view-label)
                          'face '(:weight bold :underline t)))
      (insert "\n")
      (dolist (f modified)
        (let* ((title (writing-hub--file-title f))
               (counts (gethash f per-file '(0 . 0)))
               (fa (car counts))
               (fd (cdr counts)))
          (insert "  ")
          (insert (propertize title
                              'face '(:foreground "#f9e2af")
                              'writing-hub-file f
                              'mouse-face 'highlight))
          (when (> fa 0)
            (insert (propertize (format "  +%d" fa) 'face '(:foreground "#a6e3a1"))))
          (when (> fd 0)
            (insert (propertize (format "  -%d" fd) 'face '(:foreground "#f38ba8"))))
          (insert "\n")))
      (insert "\n"))
    ;; Deleted section
    (when deleted
      (insert (propertize (format "  Deleted %s\n" view-label)
                          'face '(:weight bold :underline t)))
      (insert "\n")
      (dolist (f deleted)
        (let* ((title (if (file-exists-p f)
                          (writing-hub--file-title f)
                        (writing-hub--file-title-from-git f)))
               (counts (gethash f per-file '(0 . 0)))
               (fd (cdr counts)))
          (insert "  ")
          (insert (propertize title
                              'face '(:foreground "#f38ba8" :strike-through t)))
          (when (> fd 0)
            (insert (propertize (format "  -%d" fd) 'face '(:foreground "#f38ba8"))))
          (insert "\n")))
      (insert "\n"))
    ;; Empty state
    (when (and (null created) (null modified) (null deleted))
      (insert (propertize (format "  No activity %s.\n"
                                  (downcase view-label))
                          'face '(:foreground "#6c7086" :slant italic))))
    (goto-char (point-min))))

;;; Navigation

(defun writing-hub-open-file-at-point ()
  "Open the org-roam file at point."
  (interactive)
  (let ((file (get-text-property (point) 'writing-hub-file)))
    (if file
        (find-file file)
      (message "No file at point"))))

(defun writing-hub-next-entry ()
  "Move to the next file entry."
  (interactive)
  (let ((pos (next-single-property-change (point) 'writing-hub-file)))
    (when pos
      (goto-char pos)
      (unless (get-text-property pos 'writing-hub-file)
        (let ((next (next-single-property-change pos 'writing-hub-file)))
          (when next (goto-char next)))))))

(defun writing-hub-prev-entry ()
  "Move to the previous file entry."
  (interactive)
  (let ((pos (previous-single-property-change (point) 'writing-hub-file)))
    (when pos
      (goto-char pos)
      (unless (get-text-property pos 'writing-hub-file)
        (let ((prev (previous-single-property-change pos 'writing-hub-file)))
          (when prev (goto-char prev)))))))

(defun writing-hub-refresh ()
  "Refresh the writing hub buffer."
  (interactive)
  (writing-hub--render)
  (message "Writing hub refreshed."))

(defun writing-hub-toggle-view ()
  "Toggle between today and week view."
  (interactive)
  (setq writing-hub--view (if (eq writing-hub--view 'today) 'week 'today))
  (writing-hub--render)
  (message "View: %s" (writing-hub--view-label)))

(defun writing-hub-prev-day ()
  "View the previous day's stats."
  (interactive)
  (when (eq writing-hub--view 'week)
    (setq writing-hub--view 'today))
  (cl-decf writing-hub--day-offset)
  (writing-hub--render)
  (message "%s" (writing-hub--view-label)))

(defun writing-hub-next-day ()
  "View the next day's stats.  Won't go past today."
  (interactive)
  (when (eq writing-hub--view 'week)
    (setq writing-hub--view 'today))
  (when (< writing-hub--day-offset 0)
    (cl-incf writing-hub--day-offset)
    (writing-hub--render)
    (message "%s" (writing-hub--view-label))))

;;; Diff viewer

(defun writing-hub-diff-file-at-point ()
  "Show the diff for the file at point with word-level highlighting."
  (interactive)
  (let ((file (get-text-property (point) 'writing-hub-file)))
    (unless file
      (user-error "No file at point"))
    (let* ((default-directory writing-hub--org-dir)
           (date-str (writing-hub--viewed-date-string))
           (start-sha (cond
                       ((eq writing-hub--view 'week)
                        (writing-hub--week-baseline-sha))
                       ((= writing-hub--day-offset 0)
                        (writing-hub--baseline-sha))
                       (t (writing-hub--date-baseline-sha date-str))))
           (end-sha (cond
                     ((eq writing-hub--view 'week) nil)
                     ((= writing-hub--day-offset 0) nil)
                     (t (writing-hub--date-end-sha date-str))))
           (relative (file-relative-name file writing-hub--org-dir))
           (untracked-p (and (not end-sha)
                             (string-empty-p
                              (string-trim
                               (shell-command-to-string
                                (format "git ls-files %s 2>/dev/null"
                                        (shell-quote-argument relative)))))))
           (diff-output
            (cond
             (untracked-p
              (shell-command-to-string
               (format "git diff --no-index -- /dev/null %s 2>/dev/null"
                       (shell-quote-argument relative))))
             ((not start-sha) nil)
             (t (let ((range (if end-sha
                                 (format "%s..%s" start-sha end-sha)
                               start-sha)))
                  (shell-command-to-string
                   (format "git diff %s -- %s 2>/dev/null"
                           range (shell-quote-argument relative))))))))
      (when (and (not untracked-p) (not start-sha))
        (user-error "No baseline found for %s" date-str))
      (when (or (null diff-output) (string-empty-p (string-trim diff-output)))
        (user-error "No changes for %s" (file-name-nondirectory file)))
      (let ((buf (get-buffer-create "*writing-hub-diff*"))
            (title (if (file-exists-p file)
                       (writing-hub--file-title file)
                     (writing-hub--file-title-from-git file))))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert diff-output)
            (diff-mode)
            (setq-local diff-refine 'font-lock)
            (font-lock-ensure)
            (setq header-line-format
                  (format " %s  |  %s" title (writing-hub--view-label)))
            (goto-char (point-min))))
        (pop-to-buffer buf)
        (when (bound-and-true-p evil-mode)
          (evil-define-key 'normal 'local
            (kbd "q") #'quit-window))))))

;;; Mode

(define-derived-mode writing-hub-mode special-mode "Writing Hub"
  "Major mode for the daily writing stats dashboard."
  (setq buffer-read-only t
        truncate-lines t))

(after! evil
  (evil-define-key 'normal writing-hub-mode-map
    (kbd "j") #'writing-hub-next-entry
    (kbd "k") #'writing-hub-prev-entry
    (kbd "q") #'quit-window
    (kbd "gr") #'writing-hub-refresh
    (kbd "RET") #'writing-hub-open-file-at-point
    (kbd "TAB") #'writing-hub-toggle-view
    (kbd "C-j") #'writing-hub-next-day
    (kbd "C-k") #'writing-hub-prev-day
    (kbd "d") #'writing-hub-diff-file-at-point))

;;; Entry point

(defun writing-hub ()
  "Open the daily writing stats dashboard."
  (interactive)
  (let ((buf (get-buffer-create "*writing hub*")))
    (with-current-buffer buf
      (unless (eq major-mode 'writing-hub-mode)
        (writing-hub-mode))
      (setq writing-hub--day-offset 0)
      (writing-hub--render))
    (switch-to-buffer buf)))

(provide '+writing-hub)
;;; +writing-hub.el ends here

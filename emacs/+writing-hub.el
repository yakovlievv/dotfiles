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

;;; Date helpers

(defun writing-hub--today-date-string ()
  "Return today's date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"))

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

(defun writing-hub--offset-date (date-str n)
  "Return YYYY-MM-DD for DATE-STR offset by N days."
  (let* ((parsed (parse-time-string (concat date-str " 00:00:00")))
         (time (encode-time 0 0 0 (+ (nth 3 parsed) n) (nth 4 parsed) (nth 5 parsed))))
    (format-time-string "%Y-%m-%d" time)))

(defun writing-hub--view-label ()
  (cond
   ((eq writing-hub--view 'week) "This Week")
   ((= writing-hub--day-offset 0) "Today")
   ((= writing-hub--day-offset -1) "Yesterday")
   (t (format-time-string "%A, %b %d" (writing-hub--viewed-time)))))

;;; Baseline commit

(defun writing-hub--baseline-message ()
  "Return the baseline commit message for today."
  (format "daily-baseline: %s" (writing-hub--today-date-string)))

(defun writing-hub--baseline-exists-p ()
  "Check if a baseline commit exists for today."
  (let ((default-directory writing-hub--org-dir))
    (not (string-empty-p
          (string-trim
           (shell-command-to-string
            (format "git log --oneline --grep=%s --since='%s 00:00' 2>/dev/null"
                    (shell-quote-argument
                     (format "daily-baseline: %s" (writing-hub--today-date-string)))
                    (writing-hub--today-date-string))))))))

(defun writing-hub--baseline-sha ()
  "Return the SHA of today's baseline commit, or nil."
  (let ((default-directory writing-hub--org-dir))
    (let ((sha (string-trim
                (shell-command-to-string
                 (format "git log --format='%%H' --grep=%s --since='%s 00:00' -1 2>/dev/null"
                         (shell-quote-argument
                          (format "daily-baseline: %s" (writing-hub--today-date-string)))
                         (writing-hub--today-date-string))))))
      (unless (string-empty-p sha) sha))))

(defun writing-hub--create-baseline ()
  "Create the daily baseline commit and push.
Only stages files under roam/. Skips commit if nothing to stage."
  (let ((default-directory writing-hub--org-dir))
    (shell-command "git add -- roam/")
    (if (string-empty-p
         (string-trim (shell-command-to-string "git diff --cached --name-only")))
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

(defun writing-hub--monday-of-week-n (weeks-ago)
  "Return time for Monday 00:00 of WEEKS-AGO weeks (0 = this week)."
  (let* ((now (decode-time))
         (dow (nth 6 now))
         (days-since-mon (if (= dow 0) 6 (1- dow))))
    (encode-time 0 0 0
                 (- (nth 3 now) days-since-mon (* weeks-ago 7))
                 (nth 4 now) (nth 5 now))))

;;; Git data layer

(defun writing-hub--date-baseline-sha (date-str)
  "Return the SHA of the baseline commit for DATE-STR (YYYY-MM-DD), or nil."
  (let* ((default-directory writing-hub--org-dir)
         (next-day (writing-hub--offset-date date-str 1))
         (sha (string-trim
               (shell-command-to-string
                (format "git log --format='%%H' --grep=%s --since='%s 00:00' --until='%s 00:00' -1 2>/dev/null"
                        (shell-quote-argument (format "daily-baseline: %s" date-str))
                        date-str next-day)))))
    (unless (string-empty-p sha) sha)))

(defun writing-hub--date-end-sha (date-str)
  "Return the SHA representing the end-of-day state for DATE-STR.
For today, returns nil (meaning diff against working tree).
For past days, returns the next day's baseline, or the last commit before next day."
  (if (string= date-str (writing-hub--today-date-string))
      nil
    (let* ((default-directory writing-hub--org-dir)
           (next-day (writing-hub--offset-date date-str 1))
           (sha (writing-hub--date-baseline-sha next-day)))
      (unless sha
        (setq sha (string-trim
                   (shell-command-to-string
                    (format "git log --format='%%H' --until='%s 00:00' -1 2>/dev/null"
                            next-day)))))
      (unless (string-empty-p sha) sha))))

(defun writing-hub--first-line (str)
  "Return the first non-empty line of STR, or empty string."
  (or (car (split-string (string-trim str) "\n" t)) ""))

(defun writing-hub--week-baseline-sha (monday-time)
  "Return baseline SHA for the week starting at MONDAY-TIME.
Searches for the earliest daily-baseline commit within the given week.
Returns nil if no baseline exists for that week."
  (let* ((default-directory writing-hub--org-dir)
         (since-str (format-time-string "%Y-%m-%d" monday-time))
         (next-monday (format-time-string "%Y-%m-%d"
                        (time-add monday-time (days-to-time 7))))
         (sha (writing-hub--first-line
               (shell-command-to-string
                (format "git log --format='%%H' --grep='daily-baseline:' --since='%s' --until='%s' --reverse 2>/dev/null"
                        since-str next-monday)))))
    (unless (string-empty-p sha) sha)))

;;; File listing

(defun writing-hub--files-created-on-date (prefix)
  "Return list of org-roam files whose name starts with PREFIX."
  (let ((files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (string-prefix-p prefix (file-name-nondirectory f)))
                files)))

(defun writing-hub--files-created-in-range (prefixes)
  "Return org-roam files whose name starts with any of PREFIXES."
  (let ((files (directory-files writing-hub--roam-dir t "\\.org$")))
    (seq-filter (lambda (f)
                  (let ((name (file-name-nondirectory f)))
                    (seq-some (lambda (p) (string-prefix-p p name)) prefixes)))
                files)))

(defun writing-hub--git-diff-range (start-sha end-sha)
  "Build git diff range string from START-SHA and optional END-SHA."
  (if end-sha (format "%s..%s" start-sha end-sha) start-sha))

(defun writing-hub--files-deleted (start-sha end-sha)
  "Return list of roam files deleted between START-SHA and END-SHA.
END-SHA nil means diff against working tree."
  (let ((default-directory writing-hub--org-dir))
    (when start-sha
      (let* ((output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=D %s -- roam/ 2>/dev/null"
                               (writing-hub--git-diff-range start-sha end-sha)))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n"))))
        (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))))

(defun writing-hub--files-modified (created start-sha end-sha)
  "Return files modified (not created) between START-SHA and END-SHA.
CREATED is a list of created files to exclude."
  (let ((default-directory writing-hub--org-dir))
    (when start-sha
      (let* ((output (string-trim
                      (shell-command-to-string
                       (format "git diff --name-only --diff-filter=M %s -- roam/ 2>/dev/null"
                               (writing-hub--git-diff-range start-sha end-sha)))))
             (lines (unless (string-empty-p output)
                      (split-string output "\n")))
             (abs-files (mapcar (lambda (rel) (expand-file-name rel writing-hub--org-dir)) lines)))
        (seq-filter (lambda (f) (not (member f created))) abs-files)))))

;;; Word counting

(defun writing-hub--metadata-line-p (line)
  "Return non-nil if LINE is org metadata (#+keyword, property drawer, etc)."
  (let ((trimmed (string-trim-left line)))
    (or (string-prefix-p "#+" trimmed)
        (string-prefix-p ":" trimmed)
        (string-match-p "^\\(CLOCK:\\|DEADLINE:\\|SCHEDULED:\\|CLOSED:\\)" trimmed))))

(defun writing-hub--strip-org-links (line)
  "Strip org links from LINE, keeping only descriptions.
[[target][description]] -> description, [[target]] -> removed."
  (let ((result line))
    (setq result (replace-regexp-in-string
                  "\\[\\[[^]]*\\]\\[\\([^]]*\\)\\]\\]" "\\1" result))
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
      (if (file-exists-p file)
          (writing-hub--count-file-words file)
        0))))

;;; Diff parsing (unified)

(defun writing-hub--per-file-words (start-sha end-sha created-files)
  "Parse git diff from START-SHA to END-SHA and return per-file word counts.
Returns a hash table: absolute-file-path -> (added . deleted).
END-SHA nil means diff against working tree.
CREATED-FILES are files whose full word count is added if not in the diff."
  (let ((default-directory writing-hub--org-dir)
        (result (make-hash-table :test 'equal))
        current-file file-added file-deleted)
    (cl-flet ((flush ()
                (when current-file
                  (let ((prev (gethash current-file result '(0 . 0))))
                    (puthash current-file
                             (cons (+ (car prev) file-added)
                                   (+ (cdr prev) file-deleted))
                             result)))))
      (when start-sha
        (let ((diff-output (shell-command-to-string
                            (format "git -c core.quotepath=false diff %s -- roam/ 2>/dev/null"
                                    (writing-hub--git-diff-range start-sha end-sha)))))
          (dolist (line (split-string diff-output "\n"))
            (cond
             ((string-prefix-p "+++ b/" line)
              (flush)
              (setq current-file (expand-file-name (substring line 6) writing-hub--org-dir)
                    file-added 0
                    file-deleted 0))
             ((string-prefix-p "+++ " line)
              (flush)
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
          (flush)
          ;; Created files not already in the diff (untracked at baseline time)
          (dolist (file created-files)
            (unless (gethash file result)
              (let ((words (if end-sha
                               (writing-hub--count-file-words-at-rev file end-sha)
                             (if (file-exists-p file)
                                 (writing-hub--count-file-words file)
                               0))))
                (when (> words 0)
                  (puthash file (cons words 0) result))))))))
    result))

(defun writing-hub--words-total (per-file-hash)
  "Sum all per-file word counts. Returns (total-added . total-deleted)."
  (let ((added 0) (deleted 0))
    (maphash (lambda (_file counts)
               (setq added (+ added (car counts))
                     deleted (+ deleted (cdr counts))))
             per-file-hash)
    (cons added deleted)))

;;; View-aware dispatch

(defun writing-hub--get-start-sha ()
  "Return the start SHA for the current view."
  (cond
   ((eq writing-hub--view 'week)
    (writing-hub--week-baseline-sha (writing-hub--week-start)))
   (t (let ((date-str (writing-hub--viewed-date-string)))
        (if (= writing-hub--day-offset 0)
            (writing-hub--baseline-sha)
          (writing-hub--date-baseline-sha date-str))))))

(defun writing-hub--get-end-sha ()
  "Return the end SHA for the current view (nil = working tree)."
  (cond
   ((eq writing-hub--view 'week) nil)
   ((= writing-hub--day-offset 0) nil)
   (t (writing-hub--date-end-sha (writing-hub--viewed-date-string)))))

(defun writing-hub--get-created ()
  (if (eq writing-hub--view 'week)
      (writing-hub--files-created-in-range (writing-hub--week-date-prefixes))
    (writing-hub--files-created-on-date (writing-hub--viewed-prefix))))

(defun writing-hub--get-modified (created start-sha end-sha)
  (writing-hub--files-modified created start-sha end-sha))

(defun writing-hub--get-deleted (start-sha end-sha)
  (writing-hub--files-deleted start-sha end-sha))

(defun writing-hub--get-words (start-sha end-sha created)
  (writing-hub--per-file-words start-sha end-sha created))

;;; Statistics (average & comparison)

(defun writing-hub--words-between (start-sha end-sha)
  "Return total words added between START-SHA and END-SHA, or nil."
  (when (and start-sha end-sha)
    (car (writing-hub--words-total
          (writing-hub--per-file-words start-sha end-sha '())))))

(defun writing-hub--prev-day-words ()
  "Return total words added on the day before viewed day, or nil."
  (let* ((viewed (writing-hub--viewed-date-string))
         (prev (writing-hub--offset-date viewed -1))
         (start (writing-hub--date-baseline-sha prev))
         (end (writing-hub--date-baseline-sha viewed)))
    (writing-hub--words-between start end)))

(defun writing-hub--daily-average (n)
  "Average daily words over up to N days before viewed day.
Finds all daily-baseline commits in the range.  For each consecutive
pair of baselines, computes words added in that day.  Returns the
average across those days.  If the viewed day is today, also includes
today's work (baseline to working tree) in the average."
  (let* ((default-directory writing-hub--org-dir)
         (viewed (writing-hub--viewed-date-string))
         (range-start (writing-hub--offset-date viewed (- n)))
         (next-viewed (writing-hub--offset-date viewed 1))
         (output (string-trim
                  (shell-command-to-string
                   (format "git log --format='%%H' --grep='daily-baseline:' --since='%s 00:00' --until='%s 00:00' --reverse 2>/dev/null"
                           range-start next-viewed))))
         (lines (unless (string-empty-p output) (split-string output "\n")))
         (shas (mapcar (lambda (l) (car (split-string l))) lines)))
    (when (>= (length shas) 2)
      (let ((total 0)
            (day-count 0))
        (dotimes (i (1- (length shas)))
          (let ((words (writing-hub--words-between (nth i shas) (nth (1+ i) shas))))
            (when words
              (setq total (+ total words)
                    day-count (1+ day-count)))))
        ;; If viewing today, include today's work (last baseline to working tree)
        (when (string= viewed (writing-hub--today-date-string))
          (let* ((today-sha (car (last shas)))
                 (today-words (car (writing-hub--words-total
                                    (writing-hub--per-file-words today-sha nil '())))))
            (when (and today-words (> today-words 0))
              (setq total (+ total today-words)
                    day-count (1+ day-count)))))
        (when (> day-count 0)
          (/ total day-count))))))

(defun writing-hub--this-week-daily-average ()
  "Average words per day this week (earliest baseline this week to now).
Diffs against working tree to include today's work, divides by
days elapsed including today."
  (let* ((default-directory writing-hub--org-dir)
         (monday (writing-hub--monday-of-week-n 0))
         (since-str (format-time-string "%Y-%m-%d" monday))
         ;; Only use a baseline from THIS week — no fallback to older commits
         (start (let ((sha (writing-hub--first-line
                            (shell-command-to-string
                             (format "git log --format='%%H' --grep='daily-baseline:' --since='%s' --reverse 2>/dev/null"
                                     since-str)))))
                  (unless (string-empty-p sha) sha)))
         (now (decode-time))
         (dow (nth 6 now))
         (days-since-mon (if (= dow 0) 6 (1- dow)))
         (days (max 1 (1+ days-since-mon))))
    (when start
      (let ((total (car (writing-hub--words-total
                         (writing-hub--per-file-words start nil '())))))
        (when (and total (> total 0)) (/ total days))))))

(defun writing-hub--prev-week-words ()
  "Return total words added during the previous week, or nil."
  (let ((start (writing-hub--week-baseline-sha (writing-hub--monday-of-week-n 1)))
        (end (writing-hub--week-baseline-sha (writing-hub--monday-of-week-n 0))))
    (when (and start end (not (string= start end)))
      (writing-hub--words-between start end))))

(defun writing-hub--weekly-average (n)
  "Average weekly words over the last N completed weeks.
Uses a single diff spanning the range for efficiency."
  (let ((start (writing-hub--week-baseline-sha (writing-hub--monday-of-week-n n)))
        (end (writing-hub--week-baseline-sha (writing-hub--monday-of-week-n 0))))
    (when (and start end (not (string= start end)))
      (let ((total (writing-hub--words-between start end)))
        (when (and total (> total 0)) (/ total n))))))

;;; Rendering

(defun writing-hub--file-title (file)
  "Extract #+title: from FILE, or return the file base name."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file nil 0 500)
        (if (re-search-forward "^#\\+title:\\s-*\\(.*\\)" nil t)
            (match-string 1)
          (file-name-base file)))
    (error (file-name-base file))))

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

(defun writing-hub--render-file-entry (file per-file color &optional deleted-p)
  "Render a single file entry line.
COLOR is the title color. DELETED-P means the file was deleted."
  (let* ((title (if (and deleted-p (not (file-exists-p file)))
                    (writing-hub--file-title-from-git file)
                  (writing-hub--file-title file)))
         (counts (gethash file per-file '(0 . 0)))
         (fa (car counts))
         (fd (cdr counts))
         (face (if deleted-p
                   `(:foreground ,color :strike-through t)
                 `(:foreground ,color))))
    (insert "  ")
    (insert (propertize title
                        'face face
                        'writing-hub-file (unless deleted-p file)
                        'mouse-face (unless deleted-p 'highlight)))
    (when (> fa 0)
      (insert (propertize (format "  +%d" fa) 'face '(:foreground "#a6e3a1"))))
    (when (> fd 0)
      (insert (propertize (format "  -%d" fd) 'face '(:foreground "#f38ba8"))))
    (insert "\n")))

(defun writing-hub--render-section (label files per-file color &optional deleted-p)
  "Render a section with LABEL header and FILES list."
  (when files
    (insert (propertize (format "  %s\n" label)
                        'face '(:weight bold :underline t)))
    (insert "\n")
    (dolist (f files)
      (writing-hub--render-file-entry f per-file color deleted-p))
    (insert "\n")))

(defun writing-hub--render ()
  "Render the writing hub buffer."
  (let* ((inhibit-read-only t)
         (view-label (writing-hub--view-label))
         (start-sha (writing-hub--get-start-sha))
         (end-sha (writing-hub--get-end-sha))
         (created (writing-hub--get-created))
         (per-file (writing-hub--get-words start-sha end-sha created))
         (modified-raw (writing-hub--get-modified created start-sha end-sha))
         (deleted-raw (writing-hub--get-deleted start-sha end-sha))
         ;; For today only: detect deleted files not caught by git
         ;; (e.g. untracked files removed before commit).
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
    (insert "\n")
    ;; Average and comparison
    (let* ((is-week (eq writing-hub--view 'week))
           (avg (if is-week
                    (writing-hub--weekly-average 4)
                  (writing-hub--daily-average 7)))
           (prev-words (if is-week
                           (writing-hub--prev-week-words)
                         (writing-hub--prev-day-words)))
           (period-label (if is-week "/week" "/day"))
           (prev-label (if is-week "last week"
                         (if (= writing-hub--day-offset 0) "yesterday" "prev day"))))
      (insert "  ")
      (when avg
        (insert (propertize (format "avg %d%s" avg period-label)
                            'face '(:foreground "#9399b2"))))
      (when (and (not is-week) avg)
        (let ((week-avg (writing-hub--this-week-daily-average)))
          (when week-avg
            (insert "  |  ")
            (insert (propertize (format "avg %d/day this week" week-avg)
                                'face '(:foreground "#9399b2"))))))
      (when (and avg prev-words) (insert "  |  "))
      (when prev-words
        (let ((diff (- words-added prev-words)))
          (cond
           ((> diff 0)
            (insert (propertize (format "+%d vs %s" diff prev-label)
                                'face '(:foreground "#a6e3a1"))))
           ((< diff 0)
            (insert (propertize (format "%d vs %s" diff prev-label)
                                'face '(:foreground "#f38ba8"))))
           (t
            (insert (propertize (format "same as %s" prev-label)
                                'face '(:foreground "#9399b2")))))))
      (when (or avg prev-words) (insert "\n")))
    (insert "\n")
    ;; File sections
    (writing-hub--render-section (format "Created %s" view-label) created per-file "#89b4fa")
    (writing-hub--render-section (format "Modified %s" view-label) modified per-file "#f9e2af")
    (writing-hub--render-section (format "Deleted %s" view-label) deleted per-file "#f38ba8" t)
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
           (start-sha (writing-hub--get-start-sha))
           (end-sha (writing-hub--get-end-sha))
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
             (t (shell-command-to-string
                 (format "git diff %s -- %s 2>/dev/null"
                         (writing-hub--git-diff-range start-sha end-sha)
                         (shell-quote-argument relative)))))))
      (when (and (not untracked-p) (not start-sha))
        (user-error "No baseline found for %s" (writing-hub--viewed-date-string)))
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

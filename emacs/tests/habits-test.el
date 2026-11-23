;;; habits-test.el --- generated from doom-config.org -*- lexical-binding: t; -*-
(require 'ert)
(require 'org)
(require 'org-habit)
(require 'org-agenda)
(require 'org-id)
(setq org-id-locations-file (make-temp-file "habits-test-ids"))

(defun +repeat-skip-dates (&optional pom)
  "The dates in the :SKIP: property of the entry at POM, as \"YYYY-MM-DD\"."
  (let ((v (org-entry-get pom "SKIP")) (start 0) out)
    (while (and v (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" v start))
      (push (match-string 0 v) out)
      (setq start (match-end 0)))
    (nreverse out)))

(defun +repeat-skipped-p (day &optional pom)
  "Non-nil when DAY (a time or \"YYYY-MM-DD\") is in the :SKIP: of the entry at POM."
  (member (if (stringp day) day (format-time-string "%Y-%m-%d" day))
          (+repeat-skip-dates pom)))

(defun +repeat-skip-add (day &optional pom)
  "Add DAY (\"YYYY-MM-DD\") to the :SKIP: of the entry at POM, once, sorted.
Dates before the entry's SCHEDULED date go: they can't occur any more."
  (let* ((s (org-entry-get pom "SCHEDULED"))
         (from (and s (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" s) (match-string 0 s)))
         (dates (seq-remove (lambda (d) (and from (string< d from)))
                            (sort (delete-dups (cons day (+repeat-skip-dates pom))) #'string<))))
    (if dates
        (org-entry-put pom "SKIP" (string-join dates " "))
      (org-entry-delete pom "SKIP"))))

(with-no-warnings (defvar date))

(defun +repeat-skip-agenda ()
  "For `org-agenda-skip-function-global': hide an entry on a date its :SKIP: lists."
  (when (and (boundp 'date) (consp date) (= (length date) 3))
    (when (+repeat-skipped-p (format "%04d-%02d-%02d" (nth 2 date) (nth 0 date) (nth 1 date)))
      (save-excursion (or (outline-next-heading) (point-max))))))

(with-eval-after-load 'org-agenda
  (setq org-agenda-skip-function-global #'+repeat-skip-agenda))

(defvar +habits-file (expand-file-name "~/org/roam/20261025131500-my_habits.org")
  "The habits note: the source of every habit.")

(defun +habits--never-blocked-a (fn change-plist)
  "Around org's TODO dependencies: a habit can go DONE with steps still
open, so ticking it never fails, from the phone neither."
  (or (equal (org-entry-get (plist-get change-plist :position) "STYLE") "habit")
      (funcall fn change-plist)))

(advice-add 'org-block-todo-from-children-or-siblings-or-parent
            :around #'+habits--never-blocked-a)
(advice-add 'org-block-todo-from-checkboxes
            :around #'+habits--never-blocked-a)

(defun +routines--fresh (text)
  "TEXT, part of a subtree, as a fresh copy for a day.
Every heading in a done state is TODO again and cookies are empty;
:ID: lines, LOGBOOKs and CLOSED stamps go, so no ID is doubled in the
vault and nothing reads as done already; checkboxes are unticked.
From the routines note,
whose routines are plain headings, every heading without a keyword
becomes a TODO too, and one with sub-headings gets a [/] cookie. Call
it in the buffer TEXT comes from: its `org-done-keywords' are the ones
reset."
  (let ((case-fold-search nil))
    (when org-done-keywords
      (setq text (replace-regexp-in-string
                  (concat "^\\(\\*+ \\)" (regexp-opt org-done-keywords) "\\_>")
                  "\\1TODO" text t)))
    (when (and (bound-and-true-p +routines-file) buffer-file-name
               (file-equal-p buffer-file-name +routines-file))
      (let ((keyword (concat (regexp-opt org-todo-keywords-1) "\\_>")))
        (setq text (with-temp-buffer
                     (insert text)
                     (goto-char (point-min))
                     (while (re-search-forward "^\\(\\*+\\) " nil t)
                       (let ((level (length (match-string 1))))
                         (unless (looking-at-p keyword) (insert "TODO "))
                         (unless (looking-at-p ".*\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]")
                           (end-of-line)
                           (when (save-excursion
                                   (and (re-search-forward "^\\(\\*+\\) " nil t)
                                        (> (length (match-string 1)) level)))
                             (delete-horizontal-space)
                             ;; before its tags, if any
                             (beginning-of-line)
                             (re-search-forward "[ \t]*\\(?:[ \t]:[[:alnum:]_@#%:]+:\\)?[ \t]*$")
                             (goto-char (match-beginning 0))
                             (insert " [/]")))))
                     (buffer-string)))))
    (dolist (re '("^[ \t]*:ID:.*\n?"
                  "^[ \t]*:LOGBOOK:[ \t]*\n\\(?:.*\n\\)*?[ \t]*:END:[ \t]*\n?"
                  "^[ \t]*CLOSED: \\[[^]\n]*\\][ \t]*\n"
                  "CLOSED: \\[[^]\n]*\\] *"
                  "^[ \t]*:PROPERTIES:[ \t]*\n[ \t]*:END:[ \t]*\n?"))
      (setq text (replace-regexp-in-string re "" text t t)))
    ;; checkboxes unticked
    (setq text (replace-regexp-in-string
                "^\\([ \t]*\\(?:[-+]\\|[0-9]+[.)]\\) \\)\\[[X-]\\]" "\\1[ ]" text t))
    (setq text (replace-regexp-in-string "\\[[0-9]+/[0-9]+\\]" "[/]" text t t))
    (replace-regexp-in-string "\\[[0-9]+%\\]" "[%]" text t t)))

(defun +routines--first-step (end)
  "Start of the first step (a checkbox or a sub-heading) after point, or END."
  (if (re-search-forward "^\\(?:\\*+ \\|[ \t]*\\(?:[-+]\\|[0-9]+[.)]\\) \\[[ X-]\\]\\)" end t)
      (line-beginning-position)
    end))

(defun +routines--untitle (title)
  "TITLE without its statistics cookie."
  (string-trim (replace-regexp-in-string "\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]" "" title t t)))

(defun +routines--shift-levels (text delta)
  "TEXT with every heading moved DELTA levels."
  (if (zerop delta)
      text
    (replace-regexp-in-string
     "^\\(\\*+\\) "
     (lambda (m) (concat (make-string (max 1 (+ (length (match-string 1 m)) delta)) ?*) " "))
     text t t)))

(defun +journal--day-time ()
  "The date of the journal day heading at point, as a time, or nil."
  (let ((h (org-get-heading t t t t)))
    (when (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" h)
      (encode-time 0 0 12
                   (string-to-number (match-string 3 h))
                   (string-to-number (match-string 2 h))
                   (string-to-number (match-string 1 h))))))

(require 'calendar)
(require 'color)
(require 'subr-x)
(require 'org-habit-stats)

(defvar +habits-heatmap-weeks 26
  "Weeks a heatmap covers when nobody asks for a number, this one included.")

(defun +habits-heatmap--date (day)
  "YYYY-MM-DD of absolute DAY."
  (pcase-let ((`(,m ,d ,y) (calendar-gregorian-from-absolute day)))
    (format "%04d-%02d-%02d" y m d)))

(defun +habits-heatmap--start (today weeks)
  "Absolute day of the Monday that opens WEEKS columns ending in TODAY's week."
  (- today
     (mod (1- (calendar-day-of-week (calendar-gregorian-from-absolute today))) 7)
     (* 7 (1- weeks))))

(defun +habits-heatmap--level (value)
  "GitHub's shade 0–4 for VALUE, the share done: quarters, rounded up."
  (if (<= value 0) 0 (min 4 (ceiling (* 4 value)))))

(defun +habits-heatmap--streak (counts today)
  "Days in a row with something done in COUNTS, back from TODAY or yesterday."
  (let ((day (if (gethash today counts) today (1- today)))
        (n 0))
    (while (gethash day counts)
      (setq n (1+ n) day (1- day)))
    n))

(defun +habits-heatmap--record (days)
  "Longest run of consecutive DAYS (absolute day numbers)."
  (let ((best 0) (run 0) prev)
    (dolist (d (sort (copy-sequence days) #'<) best)
      (setq run (if (and prev (= d (1+ prev))) (1+ run) 1)
            best (max best run)
            prev d))))

(defun +habits-heatmap--grid (counts total start weeks today)
  "WEEKS columns of 7 cells from START, shaded by COUNTS out of TOTAL."
  (apply #'vector
         (cl-loop
          for w below weeks collect
          (apply #'vector
                 (cl-loop
                  for d below 7
                  for day = (+ start (* 7 w) d)
                  for n = (if (> day today) 0 (gethash day counts 0))
                  for value = (/ (float (min n total)) (max 1 total))
                  collect `((date . ,(+habits-heatmap--date day))
                            (count . ,n)
                            (value . ,value)
                            (level . ,(+habits-heatmap--level value))
                            (future . ,(if (> day today) t :json-false))))))))

(defun +habits-heatmap--habit (today start weeks)
  "The habit at point: its stats from org-habit-stats, and its grid.
Returns (DAYS . ALIST), DAYS being the absolute days it was done."
  (let* ((data (ignore-errors (org-habit-stats-parse-todo)))
         (last (org-entry-get nil "LAST_REPEAT"))
         (days (progn
                 ;; a LOGBOOK line written twice is one day, also for the stats
                 (when data
                   (setf (nth 4 data) (sort (delete-dups (copy-sequence (nth 4 data))) #'<)))
                 (delete-dups
                  (append (and last (list (time-to-days (org-time-string-to-time last))))
                          (copy-sequence (nth 4 data))))))
         (counts (make-hash-table))
         (history (and data (org-habit-stats-get-repeat-history-old-to-new data)))
         (rev (reverse history))
         (record (if data (org-habit-stats--record-streak-full history rev data) '(0))))
    (dolist (d days) (puthash d 1 counts))
    (cons days
          `((id . ,(org-id-get))
            (title . ,(org-link-display-format (org-get-heading t t t t)))
            (done . ,(if (gethash today counts) t :json-false))
            (count . ,(length days))
            (streak . ,(if data (org-habit-stats-streak history rev data) 0))
            (record . ,(car record))
            (recordDate . ,(and (> (car record) 0) (+habits-heatmap--date (cdr record))))
            (strength . ,(if data (round (org-habit-stats-exp-smoothing-list-today history rev data)) 0))
            (month . ,(if data (/ (org-habit-stats-30-day-total history rev data) 30.0) 0.0))
            (grid . ,(+habits-heatmap--grid counts 1 start weeks today))))))

(defun +habits-heatmap-data (&optional weeks today)
  "Heatmaps of every habit in `+habits-file', as data ready for `json-encode'.
WEEKS columns (default `+habits-heatmap-weeks') ending with TODAY's week;
TODAY is an absolute day, default `org-today'. Returns an alist:
  today, start (the first Monday), weeks;
  all:    done (habits done today), total (habits), streak and record
          (days in a row with any habit done), grid;
  habits: a vector of id, title, done (today: t or :json-false), count
          (times ever done), grid, and org-habit-stats' streak, record,
          recordDate, strength (0–100) and month (share of the last 30).
A grid is a vector of week columns, each a vector of seven cells
\(Monday first): date, count, value (0…1), level (0–4), future."
  (let* ((weeks (max 1 (or weeks +habits-heatmap-weeks)))
         (today (or today (org-today)))
         (start (+habits-heatmap--start today weeks))
         (all (make-hash-table))
         habits)
    (when (file-exists-p +habits-file)
      (with-current-buffer (find-file-noselect +habits-file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (let ((state (org-get-todo-state)))
              (when (and state (not (member state org-done-keywords)))
                (let ((h (+habits-heatmap--habit today start weeks)))
                  (dolist (d (car h))
                    (puthash d (1+ (gethash d all 0)) all))
                  (push (cdr h) habits)))))
          "STYLE=\"habit\""))))
    (setq habits (nreverse habits))
    `((today . ,(+habits-heatmap--date today))
      (start . ,(+habits-heatmap--date start))
      (weeks . ,weeks)
      (all . ((done . ,(gethash today all 0))
              (total . ,(length habits))
              (streak . ,(+habits-heatmap--streak all today))
              (record . ,(+habits-heatmap--record (hash-table-keys all)))
              (grid . ,(+habits-heatmap--grid all (length habits) start weeks today))))
      (habits . ,(vconcat habits)))))

(defvar +habits-heatmap-buffer "*Habits*")

(defun +habits-heatmap--blend (a b alpha)
  "Colour ALPHA of the way from B to A, or A if either isn't a colour."
  (let ((ca (ignore-errors (color-name-to-rgb a)))
        (cb (ignore-errors (color-name-to-rgb b))))
    (if (and ca cb)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* alpha x) (* (- 1 alpha) y))) ca cb)
                       '(2)))
      a)))

(defun +habits-heatmap--colours ()
  "Five colours, level 0 to 4, from the current theme."
  (let ((bg (face-background 'default nil t))
        (fg (face-foreground 'default nil t))
        (green (or (face-foreground 'success nil t) "#40c463")))
    (vector (+habits-heatmap--blend fg bg 0.15)
            (+habits-heatmap--blend green bg 0.35)
            (+habits-heatmap--blend green bg 0.55)
            (+habits-heatmap--blend green bg 0.78)
            green)))

(defun +habits-heatmap--months (grid)
  "Month names above the columns of GRID, one per month that starts in view."
  (let* ((width (* 2 (length grid)))
         (line (make-string width ?\s))
         (free 0)
         last)
    (dotimes (w (length grid))
      (let* ((date (alist-get 'date (aref (aref grid w) 0)))
             (month (string-to-number (substring date 5 7)))
             (name (calendar-month-name month t))
             (col (* 2 w)))
        (when (and (not (eql month last)) (>= col free) (<= (+ col (length name)) width))
          (store-substring line col name)
          (setq free (+ col (length name) 1)))
        (setq last month)))
    line))

(defun +habits-heatmap--insert-grid (grid colours)
  "Insert GRID: a month line, then a row per weekday."
  (insert "     " (propertize (+habits-heatmap--months grid) 'face 'shadow) "\n")
  (dotimes (d 7)
    (insert (propertize (pcase d (0 "Mon  ") (2 "Wed  ") (4 "Fri  ") (_ "     ")) 'face 'shadow))
    (seq-doseq (week grid)
      (let ((cell (aref week d)))
        (insert (if (eq (alist-get 'future cell) t)
                    "  "
                  (concat (propertize "■" 'face `(:foreground ,(aref colours (alist-get 'level cell)))
                                      'help-echo (format "%s: %d done" (alist-get 'date cell)
                                                         (alist-get 'count cell)))
                          " ")))))
    (insert "\n")))

(defun +habits-heatmap--render (data)
  "Fill the current buffer with DATA from `+habits-heatmap-data'."
  (let ((inhibit-read-only t)
        (colours (+habits-heatmap--colours))
        (all (alist-get 'all data)))
    (erase-buffer)
    (insert (propertize "Habits" 'face 'org-level-1)
            (propertize (format "   %s  ·  %d/%d today  ·  streak %dd  ·  record %dd\n\n"
                                (alist-get 'today data) (alist-get 'done all) (alist-get 'total all)
                                (alist-get 'streak all) (alist-get 'record all))
                        'face 'shadow))
    (+habits-heatmap--insert-grid (alist-get 'grid all) colours)
    (insert "\n     " (propertize "less " 'face 'shadow))
    (dotimes (l 5) (insert (propertize "■" 'face `(:foreground ,(aref colours l))) " "))
    (insert (propertize "more" 'face 'shadow) "\n")
    (seq-doseq (h (alist-get 'habits data))
      (insert "\n" (propertize (alist-get 'title h) 'face 'org-level-2)
              (propertize (format "   %s  ·  streak %d  ·  record %d  ·  strength %d%%  ·  30d %d%%  ·  %d×\n"
                                  (if (eq (alist-get 'done h) t) "done today" "open today")
                                  (alist-get 'streak h) (alist-get 'record h) (alist-get 'strength h)
                                  (round (* 100 (alist-get 'month h))) (alist-get 'count h))
                          'face 'shadow))
      (+habits-heatmap--insert-grid (alist-get 'grid h) colours))
    (goto-char (point-min))))

(defun +habits-heatmap--fit-weeks ()
  "Weeks that fit the selected window, between 4 and 53."
  (max 4 (min 53 (/ (- (window-body-width) 6) 2))))

(define-derived-mode +habits-heatmap-mode special-mode "Habits"
  "Heatmaps of the habits in `+habits-file'."
  (setq-local revert-buffer-function
              (lambda (&rest _)
                (+habits-heatmap--render
                 (+habits-heatmap-data (+habits-heatmap--fit-weeks)))))
  (setq-local truncate-lines t))

(defun +habits/heatmap ()
  "Show the habit heatmaps in a buffer of their own."
  (interactive)
  (let ((buf (get-buffer-create +habits-heatmap-buffer)))
    (pop-to-buffer-same-window buf)
    (unless (derived-mode-p '+habits-heatmap-mode)
      (+habits-heatmap-mode))
    (revert-buffer)))

(defvar +routines-file (expand-file-name "~/org/roam/20261025133348-routines.org")
  "The routines note: every top-level heading is a routine for `SPC n j r'.")

(defun +routines--names ()
  "Titles of the routines in `+routines-file', in file order."
  (with-current-buffer (find-file-noselect +routines-file)
    (org-with-wide-buffer
     (org-map-entries (lambda () (+routines--untitle (substring-no-properties (org-get-heading t t t t))))
                      "LEVEL=1"))))

(defun +routines--copy (title level)
  "Routine TITLE as a fresh copy at LEVEL, for a DO list.
The routine and its steps as they are in the routines note, boxes
unticked, heading steps made TODOs, empty cookies and no IDs (see
`+routines--fresh'), plus :ROUTINE: (inherited), so carryover leaves it
and its steps in their day. The text before the first step (a checkbox
or a sub-heading) stays in the note; what follows it comes along."
  (with-current-buffer (find-file-noselect +routines-file)
    (org-with-wide-buffer
     (let ((pos (catch 'found
                  (org-map-entries (lambda ()
                                     (when (equal (+routines--untitle (org-get-heading t t t t)) title)
                                       (throw 'found (point))))
                                   "LEVEL=1")
                  nil)))
       (unless pos (user-error "No routine called %s in %s" title +routines-file))
       (goto-char pos)
       (let* ((end (save-excursion (org-end-of-subtree t t)))
              ;; the first step: a checkbox or a sub-heading
              (first (save-excursion
                       (org-end-of-meta-data t)
                       (+routines--first-step end)))
              (steps (string-trim-right
                      (+routines--fresh (buffer-substring-no-properties first end)))))
         (concat (make-string level ?*) " TODO " title
                 (if (string-empty-p steps) "" " [/]") "\n"
                 ":PROPERTIES:\n:ROUTINE:  " title "\n:END:\n"
                 (if (string-empty-p steps) ""
                   (concat (+routines--shift-levels steps (- level (org-current-level))) "\n"))))))))

(defun +routines-insert-into-day (title)
  "Append routine TITLE to the bottom of the DO list of the journal day at point.
Point must be on the day heading; a missing DO list is made. Returns nil,
changing nothing, when the DO list already has TITLE."
  (let ((level (org-current-level))
        (end (save-excursion (org-end-of-subtree t t))))
    (save-excursion
      (unless (re-search-forward (format "^\\*\\{%d\\} DO list\\b" (1+ level)) end t)
        (goto-char end)
        (unless (bolp) (insert "\n"))
        (insert (make-string (1+ level) ?*) " DO list [0/0]\n")
        (forward-line -1))
      (org-back-to-heading t)
      (let ((do-list (point-marker))
            (do-end (save-excursion (org-end-of-subtree t t))))
        (unless (save-excursion
                  (re-search-forward (format "^\\*+ \\(?:[A-Z]+ \\)?%s\\(?: \\[[0-9/%%]*\\]\\)?[ \t]*$"
                                             (regexp-quote title))
                                     do-end t))
          (goto-char do-end)
          (unless (bolp) (insert "\n"))
          (let ((start (point)))
            (insert (+routines--copy title (+ level 2)))
            (let ((stop (point-marker)))
              (goto-char start)
              (while (< (point) stop)
                (when (org-at-heading-p) (org-update-statistics-cookies nil))
                (forward-line 1))
              (set-marker stop nil)))
          ;; the routine is one more task in the DO list
          (goto-char do-list)
          (org-update-statistics-cookies nil)
          (set-marker do-list nil)
          t)))))

(defun +routines/insert (title)
  "Pick a routine from the routines note and append it to today's DO list."
  (interactive (list (completing-read "Routine: " (+routines--names) nil t)))
  (org-journal-new-entry t)             ; today's day, no new time entry
  (while (> (org-current-level) 1)
    (org-up-heading-safe))
  (org-back-to-heading t)
  (message (if (+routines-insert-into-day title)
               "%s added to today's DO list"
             "%s is already in today's DO list")
           title))

(defun +routines--copy-p (&optional pom)
  "Non-nil when the entry at POM is a routine copy itself (its own
:ROUTINE:, not one inherited by a step)."
  (org-entry-get pom "ROUTINE"))

(defun +routines--never-blocked-a (fn change-plist)
  "Around org's TODO dependencies: a routine copy can go DONE with steps
still open, so a skipped step can stay unticked."
  (or (+routines--copy-p (plist-get change-plist :position))
      (funcall fn change-plist)))

(advice-add 'org-block-todo-from-children-or-siblings-or-parent
            :around #'+routines--never-blocked-a)
(advice-add 'org-block-todo-from-checkboxes
            :around #'+routines--never-blocked-a)

(defun +routines--done-when-all-done-h (_n-done n-not-done)
  "On `org-after-todo-statistics-hook': a routine copy, or a step with
sub-steps, is DONE once all its sub-tasks are. A step goes TODO again
when one reopens; the routine itself stays DONE, since it may have been
closed with steps open. Not logged as a state change, so the step's own
note survives."
  (when (org-entry-get nil "ROUTINE" t)
    (let ((state (org-get-todo-state))
          (org-todo-log-states nil))
      (cond ((and (= n-not-done 0) (equal state "TODO")) (org-todo "DONE"))
            ((and (> n-not-done 0) (equal state "DONE") (not (+routines--copy-p)))
             (org-todo "TODO"))))))

(add-hook 'org-after-todo-statistics-hook #'+routines--done-when-all-done-h)

(defun +routines--done-when-all-checked-h ()
  "On `org-checkbox-statistics-hook': a routine copy whose steps are
checkboxes is DONE once its cookie is full. A step heading with boxes
goes TODO again when one is unticked; the routine itself stays DONE.
Not logged as a state change."
  (save-excursion
    (when (and (ignore-errors (org-back-to-heading t))
               (org-entry-get nil "ROUTINE" t))
      (let ((state (org-get-todo-state))
            (heading (org-get-heading t t t nil))
            (org-todo-log-states nil))
        (when (string-match "\\[\\([0-9]+\\)/\\([0-9]+\\)\\]" heading)
          (let ((done (string-to-number (match-string 1 heading)))
                (all (string-to-number (match-string 2 heading))))
            (cond ((and (> all 0) (= done all) (equal state "TODO")) (org-todo "DONE"))
                  ((and (< done all) (equal state "DONE") (not (+routines--copy-p)))
                   (org-todo "TODO")))))))))

(add-hook 'org-checkbox-statistics-hook #'+routines--done-when-all-checked-h)

(defvar +habits-test-dir nil)

(defun +habits-test--file (name text)
  (let ((f (expand-file-name name +habits-test-dir)))
    (with-temp-file f (insert text))
    f))

(defun +habits-test--today-stamp (&optional offset)
  (format-time-string "%Y-%m-%d %a" (time-add (current-time) (days-to-time (or offset 0)))))

(defun +habits-test--date (&optional offset)
  (format-time-string "%Y-%m-%d" (time-add (current-time) (days-to-time (or offset 0)))))

(defmacro +habits-test--with-vault (&rest body)
  (declare (indent 0))
  `(let* ((+habits-test-dir (make-temp-file "habits-test" t))
          (org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "STRT(s!)" "|" "DONE(d!)" "KILL(k@)")))
          (org-log-into-drawer t)
          (org-log-done 'time)
          (org-log-repeat 'time)
          (org-id-track-globally nil)
          (+habits-file
           (+habits-test--file
            "habits.org"
            (concat
             "#+title: my habits\n\n"
             "* TODO piano :music:\n"
             "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
             ":PROPERTIES:\n:ID:       src-piano\n:STYLE:    habit\n:EFFORT:   0:25\n"
             ":LAST_REPEAT: [" (+habits-test--today-stamp -2) " 20:00]\n:END:\n"
             ":LOGBOOK:\n- State \"DONE\"       from \"TODO\"       [" (+habits-test--today-stamp -2) " 20:00]\n:END:\n"
             "Play scales first.\n"
             "** TODO scales\n"
             "- [ ] C major\n"
             "* TODO weekly review\n"
             "SCHEDULED: <" (+habits-test--today-stamp 3) " ++1w>\n"
             ":PROPERTIES:\n:ID:       src-weekly\n:STYLE:    habit\n:END:\n"
             ;; two body-less habits in a row, like the real note
             "* TODO stretch\n"
             "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
             ":PROPERTIES:\n:ID:       src-stretch\n:STYLE:    habit\n:END:\n"
             ":LOGBOOK:\n- State \"DONE\"       from \"TODO\"       [" (+habits-test--today-stamp -2) " 09:00]\n:END:\n\n"
             "* TODO read\n"
             "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
             ":PROPERTIES:\n:ID:       src-read\n:STYLE:    habit\n:END:\n")))
          (journal
           (+habits-test--file
            "week.org"
            (concat "#+title: Week\n\n"
                    "* Sunday, " (+habits-test--date) "\n"
                    ":PROPERTIES:\n:ID:       day-1\n:END:\n"
                    "** DO list [0/0]\n"
                    "*** TODO buy milk\n"))))
     (unwind-protect
         (with-current-buffer (find-file-noselect journal)
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p +habits-test-dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory +habits-test-dir t))))


(ert-deftest +repeat-skip-add-keeps-dates-sorted-and-alive ()
  (+habits-test--with-vault
    (with-current-buffer (find-file-noselect +habits-file)
      (let ((m (org-find-entry-with-id "src-piano")))   ; SCHEDULED yesterday
        (+repeat-skip-add (+habits-test--date 3) m)
        (+repeat-skip-add (+habits-test--date 1) m)
        (+repeat-skip-add (+habits-test--date 3) m)
        (should (equal (+repeat-skip-dates m) (list (+habits-test--date 1) (+habits-test--date 3))))
        ;; a date before SCHEDULED can't occur: it isn't kept
        (+repeat-skip-add "2020-01-01" m)
        (should (equal (+repeat-skip-dates m) (list (+habits-test--date 1) (+habits-test--date 3))))
        (let ((w (org-find-entry-with-id "src-read")))
          (+repeat-skip-add "2020-01-01" w)
          (should-not (org-entry-get w "SKIP")))))))

(ert-deftest +repeat-skip-hides-one-agenda-day ()
  (+habits-test--with-vault
    (let* ((f (+habits-test--file
               "tasks.org"
               (concat "* TODO water plants\n"
                       "SCHEDULED: <" (+habits-test--today-stamp) " +1d>\n"
                       ":PROPERTIES:\n:SKIP:     " (+habits-test--date 1) "\n:END:\n")))
           (day (lambda (n) (calendar-gregorian-from-absolute (+ (org-today) n))))
           (titles (lambda (n)
                     (mapcar (lambda (e) (get-text-property 0 'txt e))
                             (org-agenda-get-day-entries f (funcall day n) :scheduled)))))
      (should (eq org-agenda-skip-function-global #'+repeat-skip-agenda))
      (should (funcall titles 0))
      (should-not (funcall titles 1))
      (should (funcall titles 2)))))



(defmacro +routines-test--with-day (&rest body)
  "BODY in a journal file with one day (point on it), routines from a temp note."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "routines-test" t))
          (+routines-file (expand-file-name "routines.org" dir))
          (week (expand-file-name "week.org" dir)))
     (with-temp-file +routines-file
       (insert "#+title: routines\n\n"
               "* Morning routine\n:PROPERTIES:\n:ID:       r-morning\n:END:\n"
               "A simple hook to wake up fast.\n"
               "- [ ] Get out of the bed\n"
               ;; a step ticked in the note by mistake
               "- [X] Wash face\n"
               "  - [X] cold water\n"
               "- [ ] Open the daily note and plan the day\n"
               "\n*Trigger*: right after waking up\n"
               "* Session routine\n"
               "** Start :focus:\n*** Phone on DND\n"
               "** End  \n*** Clock out\n"))
     (with-temp-file week
       (insert "* Sunday, 2026-10-25\n** DO list [0/1]\n*** TODO buy milk\n* Monday, 2026-10-26\n"))
     (unwind-protect
         (with-current-buffer (find-file-noselect week)
           (goto-char (point-min))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p dir (buffer-file-name b)))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(ert-deftest +routines-names-are-the-top-level-headings ()
  (+routines-test--with-day
    (should (equal (+routines--names) '("Morning routine" "Session routine")))))

(ert-deftest +routines-append-a-fresh-copy-to-the-do-list ()
  (+routines-test--with-day
    (should (+routines-insert-into-day "Morning routine"))
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   (concat "* Sunday, 2026-10-25\n** DO list [0/2]\n*** TODO buy milk\n"
                           "*** TODO Morning routine [0/3]\n"
                           ":PROPERTIES:\n:ROUTINE:  Morning routine\n:END:\n"
                           "- [ ] Get out of the bed\n"
                           "- [ ] Wash face\n"
                           "  - [ ] cold water\n"
                           "- [ ] Open the daily note and plan the day\n"
                           "\n*Trigger*: right after waking up\n"
                           "* Monday, 2026-10-26\n")))
    ;; a second time adds nothing
    (goto-char (point-min))
    (should-not (+routines-insert-into-day "Morning routine"))
    (should (= 1 (how-many "Morning routine \\[" (point-min) (point-max))))))

(ert-deftest +routines-keep-their-sub-headings ()
  (+routines-test--with-day
    (+routines-insert-into-day "Session routine")
    (should (string-match-p
             (concat "\\*\\*\\* TODO Session routine \\[0/2\\]\n"
                     ":PROPERTIES:\n:ROUTINE:  Session routine\n:END:\n"
                     "\\*\\*\\*\\* TODO Start \\[0/1\\] +:focus:\n\\*\\*\\*\\*\\* TODO Phone on DND\n"
                     "\\*\\*\\*\\* TODO End \\[0/1\\]\n\\*\\*\\*\\*\\* TODO Clock out\n"
                     "\\* Monday")
             (buffer-string)))))

(ert-deftest +routines-are-done-when-every-step-is ()
  (+routines-test--with-day
    (+routines-insert-into-day "Morning routine")
    (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)" "KILL(k@)")))
          (org-use-property-inheritance '("ROUTINE"))
          (org-log-done nil))
      (org-mode)                        ; pick up the keywords
      (dolist (step '("Get out of the bed" "cold water" "Open the daily note and plan the day"))
        (goto-char (point-min))
        (re-search-forward (concat "\\[ \\] " (regexp-quote step)))
        (org-toggle-checkbox))
      ;; "Wash face" ticked with its only box, then the routine with all three
      (should (string-match-p "^- \\[X\\] Wash face" (buffer-string)))
      (should (string-match-p "\\*\\*\\* DONE Morning routine \\[3/3\\]" (buffer-string)))
      ;; unticking a step leaves the routine DONE (it may have been closed
      ;; with steps open)
      (goto-char (point-min))
      (re-search-forward "\\[X\\] Get out of the bed")
      (org-toggle-checkbox)
      (should (string-match-p "\\*\\*\\* DONE Morning routine \\[2/3\\]" (buffer-string))))))

(ert-deftest +routines-close-by-hand-with-boxes-open ()
  (+routines-test--with-day
    (+routines-insert-into-day "Morning routine")
    (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)" "KILL(k@)")))
          (org-use-property-inheritance '("ROUTINE"))
          (org-log-done nil))
      (org-mode)
      ;; what org-mode installs when the options are on before the buffer opens
      (let ((org-enforce-todo-dependencies t)
            (org-enforce-todo-checkbox-dependencies t)
            (org-blocker-hook (list #'org-block-todo-from-children-or-siblings-or-parent
                                    #'org-block-todo-from-checkboxes)))
        (goto-char (point-min))
        (re-search-forward "^\\*+ TODO Morning routine")
        (org-todo "DONE")
        (should (equal (org-get-todo-state) "DONE"))
        (should (string-match-p "^  - \\[ \\] cold water" (buffer-string)))
        ;; ticking a skipped step later keeps it DONE
        (goto-char (point-min))
        (re-search-forward "\\[ \\] Get out of the bed")
        (org-toggle-checkbox)
        (should (string-match-p "\\*\\*\\* DONE Morning routine \\[1/3\\]" (buffer-string)))
        ;; a plain task with an open box is still blocked
        (goto-char (point-max))
        (insert "\n*** TODO plain task\n- [ ] a box\n")
        (re-search-backward "^\\*+ TODO plain task")
        (org-todo "DONE")
        (should (equal (org-get-todo-state) "TODO"))))))

(ert-deftest +routines-stay-in-their-day-on-carryover ()
  (+routines-test--with-day
    (+routines-insert-into-day "Morning routine")
    (let* ((org-use-property-inheritance '("ROUTINE"))
           (carried (org-map-entries (lambda () (org-get-heading t t t t))
                                     "TODO=\"TODO\"-ROUTINE={.}|TODO=\"STRT\"-ROUTINE={.}")))
      (should (equal carried '("buy milk"))))))

(ert-deftest +routines-make-a-do-list-when-the-day-has-none ()
  (+routines-test--with-day
    (re-search-forward "^\\* Monday")
    (org-back-to-heading t)
    (+routines-insert-into-day "Session routine")
    (should (string-match-p "\\* Monday, 2026-10-26\n\\*\\* DO list \\[0/1\\]\n\\*\\*\\* TODO Session routine" (buffer-string)))))
(defun +habits-test--cell (grid date)
  "The cell of GRID on DATE (YYYY-MM-DD)."
  (seq-find (lambda (c) (equal (alist-get 'date c) date))
            (apply #'append (mapcar (lambda (w) (append w nil)) grid))))

(ert-deftest +habits-heatmap-level-rounds-up-to-quarters ()
  (should (equal (mapcar #'+habits-heatmap--level '(0 0.1 0.25 0.33 0.5 0.67 0.75 0.9 1))
                 '(0 1 1 2 2 3 3 4 4))))

(ert-deftest +habits-heatmap-columns-start-on-monday ()
  (let ((mon (calendar-absolute-from-gregorian '(10 26 2026)))
        (sun (calendar-absolute-from-gregorian '(10 25 2026))))
    (should (equal (+habits-heatmap--date (+habits-heatmap--start mon 1)) "2026-10-26"))
    (should (equal (+habits-heatmap--date (+habits-heatmap--start sun 1)) "2026-10-19"))
    (should (equal (+habits-heatmap--date (+habits-heatmap--start sun 3)) "2026-10-05"))))

(ert-deftest +habits-heatmap-streaks ()
  (let ((counts (make-hash-table)))
    (dolist (d '(10 11 12 20 21)) (puthash d 1 counts))
    (should (= 2 (+habits-heatmap--streak counts 21)))
    (should (= 2 (+habits-heatmap--streak counts 22))) ; today still open
    (should (= 0 (+habits-heatmap--streak counts 23)))
    (should (= 3 (+habits-heatmap--record '(21 10 12 11 20))))
    (should (= 0 (+habits-heatmap--record nil)))))

(ert-deftest +habits-heatmap-data-reads-the-logbooks ()
  (+habits-test--with-vault
    (let* ((data (+habits-heatmap-data 2))
           (all (alist-get 'all data))
           (habits (append (alist-get 'habits data) nil))
           (piano (seq-find (lambda (h) (equal (alist-get 'id h) "src-piano")) habits))
           (two-ago (+habits-test--date -2)))
      (should (equal (alist-get 'today data) (+habits-test--date)))
      (should (= 2 (alist-get 'weeks data)))
      (should (= 2 (length (alist-get 'grid all))))
      (should (= 4 (alist-get 'total all)))
      (should (= 0 (alist-get 'done all)))
      (should (equal (mapcar (lambda (h) (alist-get 'title h)) habits)
                     '("piano" "weekly review" "stretch" "read")))
      ;; LOGBOOK and LAST_REPEAT on the same day count once
      (should (= 1 (alist-get 'count piano)))
      (should (eq :json-false (alist-get 'done piano)))
      ;; org-habit-stats' numbers
      (should (= 1 (alist-get 'record piano)))
      (should (equal two-ago (alist-get 'recordDate piano)))
      (should (= 0 (alist-get 'streak piano)))
      (should (< 0 (alist-get 'strength piano) 100))
      (should (= (/ 1 30.0) (alist-get 'month piano)))
      (let ((cell (+habits-test--cell (alist-get 'grid all) two-ago)))
        (should (= 2 (alist-get 'count cell)))
        (should (= 0.5 (alist-get 'value cell)))
        (should (= 2 (alist-get 'level cell))))
      (should (= 4 (alist-get 'level (+habits-test--cell (alist-get 'grid piano) two-ago))))
      ;; this week's Sunday is still to come, unless today is Sunday
      (unless (= 0 (calendar-day-of-week (calendar-current-date)))
        (should (eq t (alist-get 'future (aref (aref (alist-get 'grid all) 1) 6)))))
      ;; it's valid JSON for the phone
      (should (json-encode data)))))

(ert-deftest +habits-heatmap-weekly-streak-counts-weeks ()
  (+habits-test--with-vault
    (with-current-buffer (find-file-noselect +habits-file)
      (goto-char (point-min))
      (re-search-forward "src-weekly\n:STYLE:    habit\n:END:\n")
      ;; done on its day three weeks running
      (insert ":LOGBOOK:\n"
              (mapconcat (lambda (o) (format "- State \"DONE\"       from \"TODO\"       [%s 10:00]\n"
                                             (+habits-test--today-stamp o)))
                         '(-4 -11 -18) "")
              ":END:\n"))
    (let ((weekly (seq-find (lambda (h) (equal (alist-get 'id h) "src-weekly"))
                            (alist-get 'habits (+habits-heatmap-data 4)))))
      (should (= 3 (alist-get 'count weekly)))
      (should (= 3 (alist-get 'streak weekly))))))

(ert-deftest +habits-heatmap-streak-includes-today ()
  (+habits-test--with-vault
    (with-current-buffer (find-file-noselect +habits-file)
      (goto-char (point-min))
      (re-search-forward "src-read\n:STYLE:    habit\n")
      ;; LAST_REPEAT and the newest LOGBOOK line on the same day, as org writes them
      (insert ":LAST_REPEAT: [" (+habits-test--today-stamp) " 08:00]\n:END:\n:LOGBOOK:\n"
              "- State \"DONE\"       from \"TODO\"       [" (+habits-test--today-stamp) " 08:00]\n"
              "- State \"DONE\"       from \"TODO\"       [" (+habits-test--today-stamp -1) " 08:00]\n")
      (re-search-forward "^:END:\n")
      (replace-match ":END:\n"))
    (let ((read (seq-find (lambda (h) (equal (alist-get 'id h) "src-read"))
                          (alist-get 'habits (+habits-heatmap-data 2)))))
      (should (eq t (alist-get 'done read)))
      (should (= 2 (alist-get 'count read)))
      (should (= 2 (alist-get 'streak read))))))

(ert-deftest +habits-heatmap-a-doubled-log-line-is-one-day ()
  (+habits-test--with-vault
    (with-current-buffer (find-file-noselect +habits-file)
      (goto-char (point-min))
      (re-search-forward "^- State \"DONE\" .*\n" nil nil 2) ; stretch's line
      (insert (match-string 0)))
    (let ((stretch (seq-find (lambda (h) (equal (alist-get 'id h) "src-stretch"))
                             (alist-get 'habits (+habits-heatmap-data 2)))))
      (should (= 1 (alist-get 'count stretch)))
      (should (= 1 (alist-get 'record stretch))))))

(ert-deftest +habits-heatmap-leaves-out-retired-habits ()
  (+habits-test--with-vault
    (with-current-buffer (find-file-noselect +habits-file)
      (goto-char (point-min))
      (re-search-forward "^\\* TODO read")
      (replace-match "* KILL read"))
    (let ((data (+habits-heatmap-data 1)))
      (should (= 3 (alist-get 'total (alist-get 'all data))))
      (should-not (seq-find (lambda (h) (equal (alist-get 'title h) "read"))
                            (alist-get 'habits data))))))

(ert-deftest +habits-heatmap-buffer-draws-every-habit ()
  (+habits-test--with-vault
    (with-temp-buffer
      (+habits-heatmap--render (+habits-heatmap-data 8))
      (should (string-match-p "^Habits " (buffer-string)))
      (dolist (title '("piano" "weekly review" "stretch" "read"))
        (should (string-match-p (concat "^" title " ") (buffer-string))))
      ;; a month line and seven weekday rows per grid: 5 grids
      (should (= 5 (how-many "^Mon  " (point-min) (point-max))))
      (should (search-forward "■" nil t)))))

(ert-deftest +habits-a-ticked-habit-repeats-and-clears-its-boxes ()
  (require 'org-checklist)
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)")))
        (org-log-into-drawer t)
        (org-log-repeat 'time))
    (with-temp-buffer
      (org-mode)
      (insert "* TODO morning routine [1/2]\n"
              "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
              ":PROPERTIES:\n:STYLE: habit\n:RESET_CHECK_BOXES: t\n:END:\n"
              "- [X] wake up [1/1]\n- [ ] stretch\n")
      (goto-char (point-min))
      (org-todo "DONE")
      (should (equal (org-get-todo-state) "TODO"))
      (should (string-match-p ":LAST_REPEAT:" (buffer-string)))
      (should-not (string-match-p "\\[X\\]" (buffer-string)))
      (should (string-match-p "- \\[ \\] wake up" (buffer-string)))
      (should (string-match-p "- \\[ \\] stretch" (buffer-string))))))

(ert-deftest +habits-without-reset-boxes-keeps-its-ticks ()
  (require 'org-checklist)
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)")))
        (org-log-into-drawer t)
        (org-log-repeat 'time))
    (with-temp-buffer
      (org-mode)
      (insert "* TODO stretch\n"
              "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
              ":PROPERTIES:\n:STYLE: habit\n:END:\n"
              "- [X] a\n")
      (goto-char (point-min))
      (org-todo "DONE")
      (should (string-match-p "- \\[X\\] a" (buffer-string))))))

(ert-deftest +habits-with-open-steps-can-be-ticked ()
  (let ((org-todo-keywords '((sequence "TODO(t)" "|" "DONE(d!)")))
        (org-log-into-drawer t)
        (org-log-repeat 'time)
        (org-enforce-todo-dependencies t)
        (org-enforce-todo-checkbox-dependencies t)
        (org-blocker-hook (list #'org-block-todo-from-children-or-siblings-or-parent
                                #'org-block-todo-from-checkboxes)))
    (with-temp-buffer
      (org-mode)
      (insert "* TODO piano\n"
              "SCHEDULED: <" (+habits-test--today-stamp -1) " .+1d>\n"
              ":PROPERTIES:\n:STYLE: habit\n:END:\n"
              "- [ ] scales\n** TODO a sub-task\n")
      (goto-char (point-min))
      (org-todo "DONE")
      (should (string-match-p ":LAST_REPEAT:" (buffer-string))))))

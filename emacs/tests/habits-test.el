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

(defun +habits--needs-repeater-a (fn &optional pom)
  "Around `org-habit-parse-todo': a :STYLE: habit heading with no repeater
isn't a habit (nil), rather than an error.
The old habit copies in past daily notes keep :STYLE: habit but have no
repeater, and org-habit signals an error on them (the agenda failed)."
  (let ((s (org-entry-get pom "SCHEDULED")))
    (when (and s (string-match-p "[.+]?\\+[0-9]+[hdwmy]" s))
      (funcall fn pom))))

(advice-add 'org-habit-parse-todo :around #'+habits--needs-repeater-a)

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

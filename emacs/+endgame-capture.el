;;; +endgame-capture.el --- capture, sessions and day creation for the endgame -*- lexical-binding: t; -*-

;; The emacs side of "the endgame" (roam note 9b510b89-c57e-40d3-b5b3-7807cd49e469):
;; the vault is the brain, everything else is a thin client. This module is
;; how things get into the vault and how a day comes to exist:
;;
;; - the APPT keyword: appointments are their own sequence, APPT | DONE
;; - the capture menu under SPC X: i inbox, t today, a appointment, e errand
;; - SPC n j r: a routine copy gets a plain active timestamp for its day,
;;   with an optional time
;; - SPC n j s: a session, the session routine with an area and a time range,
;;   into its day's DO list, or into the upcoming note for a future day
;; - `+endgame-day-ensure': creates any day without asking anything, then
;;   moves that day's staged items from upcoming into its DO list. Making a
;;   day by hand (`+org-journal-init-day') does the same move
;; - the areas registry (`+endgame-areas'), a clocktable per area from its
;;   SOURCES (dynamic block `endgame-areas') and planned vs clocked minutes
;;
;; It builds on the doom config's `+habits-*', `+routines-*' and
;; `+org-journal-*' functions, so it loads after them, at the end of the
;; config. The functions the server calls through emacsclient
;; (`+endgame-day-ensure', `+endgame-areas-json', `+endgame-areas-report-json')
;; never prompt, save the buffers they change and return a JSON string.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'org)
(require 'org-clock)

(defvar org-time-was-given)             ; set by `org-read-date' when bound
(defvar org-end-time-was-given)
(defvar org-journal-dir)
(defvar org-journal-carryover-items)
(defvar org-journal-find-file-fn)
(defvar org-journal-hide-entries-p)
(defvar org-journal-enable-agenda-integration)
(declare-function org-journal-new-entry "org-journal")
(declare-function org-journal--get-entry-path "org-journal")
(declare-function +habits--day-time "config")
(declare-function +habits--shift-levels "config")
(declare-function +routines--copy "config")
(declare-function +routines--names "config")
(declare-function +org-journal-init-day "config")

;;; Where things live

(defvar +endgame-vault-dir (expand-file-name "~/org/")
  "The vault. `file:' sources in the areas note are relative to it.")

(defvar +endgame-areas-file
  (expand-file-name "roam/20261031030150-areas.org" +endgame-vault-dir)
  "The areas note: level 1 headings are categories, level 2 headings areas.")

(defvar +endgame-upcoming-file
  (expand-file-name "roam/20261031030202-upcoming.org" +endgame-vault-dir)
  "The staging note: day-own items for a day that doesn't exist yet.")

(defvar +endgame-life-file
  (expand-file-name "roam/20261031024752-life.org" +endgame-vault-dir)
  "The life note, with the Appointments and Errands headings.")

(defvar +endgame-inbox-file
  (expand-file-name "roam/20261031024803-inbox.org" +endgame-vault-dir)
  "The inbox note: raw captures go at its end.")

(defvar +endgame-session-routine "Session routine"
  "The routine in the routines note a session is a copy of.")

;;; Small helpers

(defun +endgame--date-time (&optional date)
  "DATE (\"YYYY-MM-DD\") as a time at noon; nil is org's today."
  (if date
      (progn
        (unless (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date)
          (error "Not a YYYY-MM-DD date: %S" date))
        (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number (split-string date "-"))))
          (encode-time 0 0 12 d m y)))
    (pcase-let ((`(,m ,d ,y) (calendar-gregorian-from-absolute (org-today))))
      (encode-time 0 0 12 d m y))))

(defun +endgame--date (time)
  "TIME as \"YYYY-MM-DD\"."
  (format-time-string "%Y-%m-%d" time))

(defun +endgame--today ()
  "Org's today (it ends at `org-extend-today-until') as \"YYYY-MM-DD\"."
  (+endgame--date (+endgame--date-time)))

(defun +endgame--buffer (file)
  "A buffer visiting FILE, re-read first if the file changed under it.
Syncthing and vault-api write these files too: editing a stale buffer
asks first, which from the server is an error."
  (let ((buf (find-buffer-visiting file)))
    (if (not buf)
        (find-file-noselect file)
      (when (and (file-exists-p file)
                 (not (buffer-modified-p buf))
                 (not (verify-visited-file-modtime buf)))
        (with-current-buffer buf (revert-buffer t t t)))
      buf)))

(defvar +endgame--saved nil
  "Files saved while the innermost `+endgame--saving' ran, newest first.")

(defvar +endgame--recording nil
  "Non-nil while `+endgame--saving' runs: saves go into `+endgame--saved'.")

(defun +endgame--record-save-a (&rest _)
  "After `basic-save-buffer': inside `+endgame--saving', remember the file.
An advice, not `after-save-hook': org buffers here carry a local value."
  (when (and +endgame--recording (buffer-file-name)
             (file-in-directory-p (buffer-file-name) +endgame-vault-dir))
    (cl-pushnew (buffer-file-name) +endgame--saved :test #'equal)))

(advice-add 'basic-save-buffer :after #'+endgame--record-save-a)

(defmacro +endgame--saving (&rest body)
  "Run BODY, then save every file buffer it left modified.
Buffers that already had unsaved changes are left alone. Every file
saved meanwhile (by BODY too) ends up in `+endgame--saved'."
  (declare (indent 0))
  (let ((dirty (make-symbol "dirty")))
    `(let ((,dirty (seq-filter #'buffer-modified-p (buffer-list)))
           (+endgame--recording t)
           ;; org-journal's after-save hook would customize-save
           ;; `org-agenda-files' into custom.el; the config builds that
           ;; list with ripgrep anyway
           (org-journal-enable-agenda-integration nil))
       (prog1 (progn ,@body)
         (dolist (buf (buffer-list))
           (when (and (buffer-file-name buf)
                      (buffer-modified-p buf)
                      (not (memq buf ,dirty)))
             (with-current-buffer buf (save-buffer))))))))

(defun +endgame--relative (file)
  "FILE relative to the vault when it's inside it."
  (let ((root (file-truename +endgame-vault-dir))
        (file (file-truename file)))
    (if (string-prefix-p root file) (substring file (length root)) file)))

(defun +endgame--json (value)
  "VALUE as a JSON string."
  (let ((json-encoding-pretty-print nil))
    (json-encode value)))

(defun +endgame--rg-files (regexp paths)
  "Files under PATHS (files or directories) with a line matching REGEXP.
ripgrep, over .org files outside templates/ and config/, sorted."
  (when-let* ((rg (executable-find "rg"))
              (paths (seq-filter #'file-exists-p paths)))
    (with-temp-buffer
      (apply #'call-process rg nil t nil
             "--files-with-matches" "--no-messages"
             "--glob" "*.org" "--glob" "!**/templates/**" "--glob" "!**/config/**"
             "-e" regexp paths)
      (sort (split-string (buffer-string) "\n" t) #'string<))))

;;; Timestamps

(defun +endgame--format-stamp (time &optional with-time end)
  "Active timestamp of TIME; WITH-TIME adds its time, END (\"HH:MM\") a range."
  (let ((s (format-time-string (org-time-stamp-format with-time) time)))
    (if (and with-time end)
        (concat (substring s 0 -1) "-" end ">")
      s)))

(defun +endgame--stamp (input &optional default fixed-day)
  "Active timestamp for INPUT, read the way org's date prompt reads it.
\"mon 2pm\", \"mon 14:00-14:45\", \"mon 2pm+0:45\", \"fri\", \"+2d\"; a
bare time (\"9:00\") is on DEFAULT's day (a time, default today). With
FIXED-DAY a time that has passed today stays today. The stamp has a
time only when INPUT gave one."
  (let ((org-time-was-given nil)
        (org-end-time-was-given nil)
        (org-read-date-prefer-future (if fixed-day nil org-read-date-prefer-future)))
    (let ((time (org-read-date nil t input nil default)))
      (+endgame--format-stamp time org-time-was-given org-end-time-was-given))))

(defun +endgame--read-stamp (prompt &optional default require-time)
  "Ask for a timestamp with org's date prompt (and calendar) after PROMPT.
DEFAULT is the time it starts at. REQUIRE-TIME: no time is an error."
  (let ((org-time-was-given nil)
        (org-end-time-was-given nil))
    (let ((time (org-read-date require-time t nil prompt default)))
      (when (and require-time (not org-time-was-given))
        (user-error "That needs a time, e.g. 14:00-15:00 or mon 2pm+0:45"))
      (+endgame--format-stamp time org-time-was-given org-end-time-was-given))))

(defun +endgame--stamp-range (stamp)
  "(DATE START END MINUTES) of the active timestamp (or range) STAMP.
DATE is \"YYYY-MM-DD\", START and END \"HH:MM\" or nil, MINUTES the
length when it has both, else nil."
  (let* ((ts (org-timestamp-from-string stamp))
         (p (lambda (k) (org-element-property k ts)))
         (start (and (funcall p :hour-start)
                     (format "%02d:%02d" (funcall p :hour-start) (funcall p :minute-start))))
         (range (and start (funcall p :hour-end)
                     (or (memq (funcall p :type) '(active-range inactive-range))
                         (not (and (= (funcall p :hour-start) (funcall p :hour-end))
                                   (= (funcall p :minute-start) (funcall p :minute-end)))))))
         (end (and range (format "%02d:%02d" (funcall p :hour-end) (funcall p :minute-end)))))
    (list (format "%04d-%02d-%02d" (funcall p :year-start) (funcall p :month-start) (funcall p :day-start))
          start end
          (and range (round (/ (float-time (time-subtract (org-timestamp-to-time ts t)
                                                          (org-timestamp-to-time ts)))
                               60))))))

(defun +endgame-entry-stamp (&optional pom)
  "The first plain active timestamp (or range) of the entry at POM, or nil.
Searched in the heading and the body before the first child; planning
lines (SCHEDULED, DEADLINE) and property lines don't count."
  (org-with-point-at (or pom (point))
    (org-with-wide-buffer
     (org-back-to-heading t)
     (let ((end (save-excursion (outline-next-heading) (point)))
           found)
       (while (and (not found) (re-search-forward org-tsr-regexp end t))
         (unless (save-excursion
                   (beginning-of-line)
                   (looking-at-p (concat "[ \t]*\\(?:" org-keyword-time-regexp
                                         "\\|:[^ \t\n]+:\\)")))
           (setq found (match-string-no-properties 0))))
       found))))

(defun +endgame-entry-time-range (&optional pom)
  "(DATE START END MINUTES) of the entry at POM's timestamp, see `+endgame--stamp-range'.
Nil when the entry has no plain active timestamp."
  (when-let ((stamp (+endgame-entry-stamp pom)))
    (+endgame--stamp-range stamp)))

(defun +endgame--title ()
  "The heading at point without keyword, priority, tags or cookies."
  (string-trim
   (replace-regexp-in-string "\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]" ""
                             (substring-no-properties (org-get-heading t t t t)))))

(defun +endgame--today-stamp ()
  "Today's date stamp, for capture templates: org's today, not the clock's."
  (+endgame--format-stamp (+endgame--date-time)))

;;; APPT

;; Appointments are events: a fixed date and time, still ticked when they
;; happened. Their own sequence keeps them apart from tasks (CalDAV maps
;; them to VEVENTs) and C-c C-t on one goes straight to DONE. The agenda
;; file scan (`my/org-agenda--todo-regexp') is derived from
;; `org-todo-keywords', so it finds APPT headings without a change.
(with-eval-after-load 'org
  (add-to-list 'org-todo-keywords '(sequence "APPT(a)" "|" "DONE(d!)") t)
  (when (boundp 'my/org-pill-todo-colors)
    (add-to-list 'my/org-pill-todo-colors '("APPT" . sky) t)
    (when (and (fboundp 'my/org-palette-faces-h) (require 'catppuccin-theme nil t))
      (my/org-palette-faces-h))))

;;; Capture: SPC X

(defun +endgame--read-title (prompt)
  "Read a non-empty title after PROMPT, escaped for a capture template."
  (let ((title (string-trim (read-string prompt))))
    (when (string-empty-p title) (user-error "Empty title"))
    (replace-regexp-in-string "%" "\\\\%" title t t)))

(defun +endgame--appt-template ()
  "Capture template for an appointment: asks the title and a time."
  (let ((title (+endgame--read-title "Appointment: ")))
    (concat "* APPT " title " "
            (+endgame--read-stamp "When (mon 2pm, mon 14:00-14:45, mon 2pm+0:45): " nil t))))

(defun +endgame--errand-template ()
  "Capture template for an errand: asks the title, and a date that may stay empty."
  (let* ((title (+endgame--read-title "Errand: "))
         (date (string-trim (read-string "Date (empty for none; fri, +2d, 11-05): "))))
    (concat "* TODO " title "\n"
            (if (string-empty-p date) ""
              (concat "SCHEDULED: " (+endgame--stamp date) "\n"))
            ":PROPERTIES:\n:CREATED:  %U\n:END:")))

(defvar +endgame-capture-templates
  '(("i" "Inbox" entry (file +endgame-inbox-file)
     "* TODO %^{Inbox}\n:PROPERTIES:\n:CREATED:  %U\n:END:"
     :immediate-finish t)
    ("t" "Today (inbox, scheduled today)" entry (file +endgame-inbox-file)
     "* TODO %^{Today}\nSCHEDULED: %(+endgame--today-stamp)\n:PROPERTIES:\n:CREATED:  %U\n:END:"
     :immediate-finish t)
    ("a" "Appointment" entry (file+headline +endgame-life-file "Appointments")
     (function +endgame--appt-template)
     :immediate-finish t)
    ("e" "Errand" entry (file+headline +endgame-life-file "Errands")
     (function +endgame--errand-template)
     :immediate-finish t))
  "The endgame's capture menu. Doom's own templates with these keys go.")

(defun +endgame-capture-setup ()
  "Put `+endgame-capture-templates' first in `org-capture-templates'."
  (let ((keys (mapcar #'car +endgame-capture-templates)))
    (setq org-capture-templates
          (append +endgame-capture-templates
                  (seq-remove (lambda (tpl) (member (car tpl) keys))
                              org-capture-templates)))))

;; Doom sets its default templates when org loads; org-capture loads later.
(with-eval-after-load 'org-capture
  (+endgame-capture-setup))

;;; Copies in a day: DO list, staging

(defun +endgame--text-level (text)
  "Level of the first heading in TEXT, or 1."
  (if (string-match "^\\(\\*+\\) " text) (length (match-string 1 text)) 1))

(defun +endgame--stamp-copy (text stamp)
  "TEXT (a copy from `+routines--copy') with STAMP on the line after its drawer."
  (if (string-match "^:END:\n" text)
      (concat (substring text 0 (match-end 0)) stamp "\n" (substring text (match-end 0)))
    (replace-regexp-in-string "\\`\\(.*\n\\)" (concat "\\1" stamp "\n") text t)))

(defun +endgame--append-to-do-list (day texts)
  "Append TEXTS (org subtrees, any level) to the DO list of DAY.
DAY is a marker at a journal day heading; a missing DO list is made.
Each text is shifted to sit under the DO list; the cookies are updated."
  (with-current-buffer (marker-buffer day)
    (org-with-wide-buffer
     (goto-char day)
     (let ((level (org-current-level))
           (end (save-excursion (org-end-of-subtree t t))))
       (unless (re-search-forward (format "^\\*\\{%d\\} DO list\\b" (1+ level)) end t)
         (goto-char end)
         (unless (bolp) (insert "\n"))
         (insert (make-string (1+ level) ?*) " DO list [0/0]\n")
         (forward-line -1))
       (org-back-to-heading t)
       (let ((do-list (point-marker)))
         (goto-char (save-excursion (org-end-of-subtree t t)))
         (unless (bolp) (insert "\n"))
         (let ((start (point)))
           (dolist (text texts)
             (insert (string-trim-right
                      (+habits--shift-levels text (- (+ level 2) (+endgame--text-level text))))
                     "\n"))
           (let ((stop (point-marker)))   ; the copies' own cookies
             (goto-char start)
             (while (< (point) stop)
               (when (org-at-heading-p) (org-update-statistics-cookies nil))
               (forward-line 1))
             (set-marker stop nil)))
         (goto-char do-list)            ; the DO list's own cookie
         (org-update-statistics-cookies nil)
         (set-marker do-list nil))))))

(defun +endgame--append-to-upcoming (text)
  "Append TEXT as a top-level heading at the end of the upcoming note."
  (with-current-buffer (+endgame--buffer +endgame-upcoming-file)
    (org-with-wide-buffer
     (goto-char (point-max))
     (unless (bolp) (insert "\n"))
     (unless (save-excursion (forward-line -1) (looking-at-p "[ \t]*$"))
       (insert "\n"))
     (let ((start (point)))
       (insert (string-trim-right (+habits--shift-levels text (- 1 (+endgame--text-level text))))
               "\n")
       (goto-char start)
       (org-update-statistics-cookies nil)))))

(defun +endgame-stage-into-day (day)
  "Move the upcoming note's items for DAY into DAY's DO list.
DAY is a marker at a journal day heading. An item is a top-level heading
of the upcoming note whose first plain active timestamp falls on that
day; it keeps its whole subtree, properties and :CALDAV_UID: included,
and is deleted from the upcoming note. Returns how many moved."
  (let ((date (with-current-buffer (marker-buffer day)
                (org-with-wide-buffer
                 (goto-char day)
                 (+endgame--date (+habits--day-time)))))
        texts)
    (when (file-exists-p +endgame-upcoming-file)
      (with-current-buffer (+endgame--buffer +endgame-upcoming-file)
        (org-with-wide-buffer
         (let (regions)
           (goto-char (point-min))
           (while (re-search-forward "^\\* " nil t)
             (let ((beg (line-beginning-position)))
               (when (equal (car (+endgame-entry-time-range beg)) date)
                 (push (cons beg (save-excursion (goto-char beg) (org-end-of-subtree t t) (point)))
                       regions))))
           ;; bottom first, so the earlier regions stay where they are
           (dolist (r regions)
             (push (buffer-substring-no-properties (car r) (cdr r)) texts)
             (delete-region (car r) (cdr r))))))
      (when texts
        (+endgame--append-to-do-list day texts)))
    (length texts)))

(defun +endgame--merge-do-lists (day)
  "Fold DAY's extra DO lists into its first one. Returns how many went.
Carryover brings the old day's DO list heading along with its items, and
day setup then makes the new day's own, so a fresh day had two."
  (with-current-buffer (marker-buffer day)
    (org-with-wide-buffer
     (goto-char day)
     (let ((re (format "^\\*\\{%d\\} DO list\\b" (1+ (org-current-level))))
           (end (save-excursion (org-end-of-subtree t t) (point-marker)))
           bodies)
       (when (re-search-forward re end t)
         (while (re-search-forward re end t)
           (let ((beg (line-beginning-position))
                 (stop (save-excursion (org-end-of-subtree t t) (point))))
             (push (buffer-substring-no-properties (min stop (1+ (line-end-position))) stop) bodies)
             (delete-region beg stop)
             (goto-char beg))))
       (set-marker end nil)
       (setq bodies (seq-remove (lambda (b) (string-blank-p b)) (nreverse bodies)))
       (when bodies (+endgame--append-to-do-list day bodies))
       (length bodies)))))

(defvar +endgame--no-staging nil
  "Non-nil: day setup leaves the staging move to its caller.")

(defun +endgame--init-day-a (fn &rest args)
  "Around `+org-journal-init-day': a day that has just been set up gets its staged items."
  (let* ((day (save-excursion
                (while (and (org-current-level) (> (org-current-level) 1))
                  (org-up-heading-safe))
                (and (org-at-heading-p) (point-marker))))
         (fresh (and day (not (org-entry-get day "ID")))))
    (prog1 (apply fn args)
      (when (and fresh (org-entry-get day "ID"))
        (+endgame--merge-do-lists day))
      (when (and fresh (not +endgame--no-staging) (org-entry-get day "ID"))
        ;; the upcoming note is saved (the day is the buffer being written
        ;; in): until then vault-api would see the items in both places
        (let* ((up (find-buffer-visiting +endgame-upcoming-file))
               (dirty (and up (buffer-modified-p up)))
               (n (+endgame-stage-into-day day)))
          (when (> n 0)
            (unless dirty
              (with-current-buffer (find-buffer-visiting +endgame-upcoming-file) (save-buffer)))
            (message "Moved %d item%s from upcoming into the day" n (if (= n 1) "" "s"))))))))

(advice-add '+org-journal-init-day :around #'+endgame--init-day-a)

;;; Days

(defun +endgame--day-marker (date)
  "Marker at the journal day heading of DATE (\"YYYY-MM-DD\"), or nil."
  (require 'org-journal)
  (let ((file (org-journal--get-entry-path (+endgame--date-time date))))
    (when (or (find-buffer-visiting file) (file-exists-p file)) ; a new week isn't saved yet
      (with-current-buffer (+endgame--buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (when (re-search-forward (format "^\\*[ \t]+.*%s" (regexp-quote date)) nil t)
           (copy-marker (line-beginning-position))))))))

(defun +endgame--create-day (time &optional ask)
  "Make TIME's day exist and set it up; return a marker at its heading.
The same path as making a day by hand: `org-journal-new-entry' writes the
week file header, the day heading and the carryover, then
`+org-journal-init-day' adds the ID, :daily:, the clocktable, the DO list
and the habits due (and, through `+endgame--init-day-a', the staging
move). Without ASK the sleep and morning prompts are answered no. Only
org's today carries open TODOs over, so making a future day never takes
today's. A day heading that exists without an ID is set up in place."
  (require 'org-journal)
  (let ((date (+endgame--date time)))
    (save-current-buffer
      (save-window-excursion
        (let ((org-journal-find-file-fn (lambda (f) (set-buffer (+endgame--buffer f))))
              (org-journal-hide-entries-p nil)
              (org-journal-carryover-items
               (if (equal date (+endgame--today)) org-journal-carryover-items "")))
          (org-journal-new-entry t time))))
    (let ((day (or (+endgame--day-marker date)
                   (error "org-journal made no heading for %s" date))))
      (with-current-buffer (marker-buffer day)
        (org-with-wide-buffer
         (goto-char day)
         (if ask
             (+org-journal-init-day)
           (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
             (+org-journal-init-day)))))
      day)))

(defun +endgame--ensure-day (date &optional ask)
  "Marker at DATE's day heading, made and set up first when it isn't yet."
  (let ((day (+endgame--day-marker date)))
    (if (and day (org-entry-get day "ID"))
        day
      (+endgame--create-day (+endgame--date-time date) ask))))

(defun +endgame-day-ensure (&optional date)
  "Make DATE's day exist, then move its staged items into it. JSON.
DATE is \"YYYY-MM-DD\", nil for org's today. Creates the day heading in
its weekly file when missing (ID, :daily:, clocktable, DO list, habits
due, carryover for today), asking nothing, then moves DATE's items from
the upcoming note into the DO list. Safe to call again. Saves what it
changes. Returns {\"date\",\"file\",\"created\",\"moved\",\"files\"}:
file is the week file (absolute), files every file it saved, relative
to the vault."
  (let ((inhibit-interaction t)
        (date (or date (+endgame--today)))
        (+endgame--saved nil)
        result)
    (+endgame--saving
      (let* ((day (+endgame--day-marker date))
             (fresh (not (and day (org-entry-get day "ID")))))
        (when fresh
          (let ((+endgame--no-staging t))
            (setq day (+endgame--create-day (+endgame--date-time date)))))
        (let ((moved (+endgame-stage-into-day day)))
          ;; these two even when an earlier, failed call left them unsaved
          (dolist (buf (list (marker-buffer day) (find-buffer-visiting +endgame-upcoming-file)))
            (when (and buf (buffer-modified-p buf))
              (with-current-buffer buf (save-buffer))))
          (setq result `((date . ,date)
                         (file . ,(buffer-file-name (marker-buffer day)))
                         (created . ,(if fresh t :json-false))
                         (moved . ,moved)))
          (set-marker day nil))))
    (+endgame--json
     (append result `((files . ,(vconcat (mapcar #'+endgame--relative (reverse +endgame--saved)))))))))

;;; Routines: SPC n j r

(defvar +endgame--routine-day nil
  "The day (a time) of the routine being inserted, while `+routines-insert-into-day' runs.")

(defvar +endgame--routine-time nil
  "The time typed for the routine being inserted: a string, empty for none.")

(defun +endgame--routine-stamp ()
  "The stamp for the routine copy being inserted: its day, and the time if one was given."
  (if (and +endgame--routine-time (not (string-empty-p +endgame--routine-time)))
      (+endgame--stamp +endgame--routine-time +endgame--routine-day t)
    (+endgame--format-stamp +endgame--routine-day)))

(defun +endgame--routines-insert-into-day-a (fn &rest args)
  "Around `+routines-insert-into-day': remember the day at point for the copy's stamp."
  (let ((+endgame--routine-day (+habits--day-time)))
    (apply fn args)))

(defun +endgame--routines-copy-a (text)
  "After `+routines--copy': a routine going into a day gets that day's timestamp."
  (if +endgame--routine-day
      (+endgame--stamp-copy text (+endgame--routine-stamp))
    text))

(defun +endgame--routines-insert-a (fn title &optional time)
  "Around `+routines/insert': ask for an optional time, and set up a new day.
A plain timestamp, not SCHEDULED: it shows on its day only, so an
unfinished copy stays in its day. A time puts it on the timeline too.
A day that doesn't exist yet is made the normal way, sleep and morning
prompts included, so it gets its habits and staged items."
  (interactive
   (list (completing-read "Routine: " (+routines--names) nil t)
         (read-string "Time (empty for none; 9:00, 9am+0:30): ")))
  (+endgame--ensure-day (+endgame--today) t)
  (let ((+endgame--routine-time (and time (string-trim time))))
    (funcall fn title)))

(advice-add '+routines-insert-into-day :around #'+endgame--routines-insert-into-day-a)
(advice-add '+routines--copy :filter-return #'+endgame--routines-copy-a)
(advice-add '+routines/insert :around #'+endgame--routines-insert-a)

;; The same, without the command: what the server calls

(defun +endgame-routine-add (title date &optional time ask)
  "Put routine TITLE into the day DATE (\"YYYY-MM-DD\"), stamped for that day.
TIME is what the time prompt reads (\"9:00\", \"9am+0:30\"), nil or empty for
none. A future day without a note gets it in the upcoming note instead; a
missing day otherwise is made first (ASK: with the sleep and morning
questions). Returns `day', `upcoming', or nil when the day already has it."
  (let ((day (+endgame--day-marker date))
        (+endgame--routine-time time))
    (if (and (not day) (string> date (+endgame--today)))
        (let ((+endgame--routine-day (+endgame--date-time date)))
          (+endgame--append-to-upcoming (+routines--copy title 1))
          'upcoming)
      (let ((day (+endgame--ensure-day date ask)))
        (with-current-buffer (marker-buffer day)
          (org-with-wide-buffer
           (goto-char day)
           (and (+routines-insert-into-day title) 'day)))))))

(defun +endgame-routine-json (title &optional date time)
  "`+endgame-routine-add' for the server: asks nothing, saves, returns JSON.
DATE nil is org's today. {\"where\": \"day\"|\"upcoming\"|\"exists\", \"files\"}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        where)
    (+endgame--saving
      (setq where (+endgame-routine-add title (or date (+endgame--today)) time)))
    (+endgame--json `((where . ,(if where (symbol-name where) "exists"))
                      (files . ,(vconcat (mapcar #'+endgame--relative (reverse +endgame--saved))))))))

;;; Areas

(defvar +endgame--areas-cache nil
  "(KEY . AREAS): the parsed areas note and what it was parsed from.")

(defun +endgame--baseline (value)
  "An H:MM baseline VALUE in minutes, or nil."
  (when (and value (string-match-p "[0-9]" value))
    (round (org-duration-to-minutes (string-trim value)))))

(defun +endgame--parse-areas ()
  "The areas of the areas note in the current buffer, in file order."
  (let (areas)
    (org-map-entries
     (lambda ()
       (let ((tag (org-entry-get nil "AREA_TAG")))
         (when (and tag (= (org-current-level) 2))
           (let ((category (save-excursion
                             (org-up-heading-safe)
                             (replace-regexp-in-string
                              "[ \t]+category\\'" ""
                              (substring-no-properties (org-get-heading t t t t)) t))))
             (push `((name . ,(substring-no-properties (org-get-heading t t t t)))
                     (category . ,category)
                     (tag . ,(string-trim tag))
                     (strategy . ,(org-entry-get nil "STRATEGY"))
                     (baselineWeek . ,(+endgame--baseline (org-entry-get nil "BASELINE_WEEK")))
                     (baselineDay . ,(+endgame--baseline (org-entry-get nil "BASELINE_DAY")))
                     (sources . ,(split-string (or (org-entry-get nil "SOURCES") "") nil t))
                     (id . ,(org-entry-get nil "ID")))
                   areas))))))
    (nreverse areas)))

(defun +endgame-areas ()
  "The areas registry: an alist per level 2 heading with an AREA_TAG.
Keys: name, category, tag, strategy, baselineWeek and baselineDay (minutes
or nil), sources (the SOURCES words), id. Never hardcoded: read from
`+endgame-areas-file' and re-read when it changes."
  (let* ((buf (+endgame--buffer +endgame-areas-file))
         (key (list +endgame-areas-file buf (buffer-modified-tick buf))))
    (if (equal (car +endgame--areas-cache) key)
        (cdr +endgame--areas-cache)
      (let ((areas (with-current-buffer buf (org-with-wide-buffer (+endgame--parse-areas)))))
        (setq +endgame--areas-cache (cons key areas))
        areas))))

(defun +endgame--area (tag)
  "The area whose AREA_TAG is TAG, or nil."
  (seq-find (lambda (a) (equal (alist-get 'tag a) tag)) (+endgame-areas)))

(defun +endgame--files-with-filetag (tag)
  "Vault files whose #+filetags has TAG (archives, templates and config left out)."
  (seq-remove (lambda (f) (string-match-p "/archive/" f))
              (+endgame--rg-files (format "^#\\+(?i:filetags):.*:%s:" (regexp-quote tag))
                                  (list +endgame-vault-dir))))

(defun +endgame-area-sources (area)
  "Where AREA's clocked time comes from: a list of (FILE . ID).
ID is nil for a whole file. AREA is an area alist or its tag. From the
SOURCES words: tag:X is every file with filetag X, file:P the file at P
from the vault, id:U the subtree of that heading."
  (let ((area (if (stringp area) (+endgame--area area) area)))
    (delete-dups
     (cl-loop
      for src in (alist-get 'sources area)
      append (cond
              ((string-prefix-p "tag:" src)
               (mapcar #'list (+endgame--files-with-filetag (substring src 4))))
              ((string-prefix-p "file:" src)
               (let ((f (expand-file-name (substring src 5) +endgame-vault-dir)))
                 (and (file-exists-p f) (list (list f)))))
              ((string-prefix-p "id:" src)
               (let* ((id (substring src 3))
                      (f (org-id-find-id-file id)))
                 (and f (list (cons f id))))))))))

(defun +endgame--area-tables (sources params)
  "Clocktable data (`org-clock-get-table-data') for each of SOURCES with PARAMS."
  (cl-loop
   for (file . id) in sources
   for table = (with-current-buffer (org-get-agenda-file-buffer file)
                 (org-with-wide-buffer
                  (when (or (not id)
                            (when-let ((pos (org-find-entry-with-id id)))
                              (goto-char pos)
                              (org-narrow-to-subtree)
                              t))
                    (org-clock-get-table-data file params))))
   when table collect table))

(defun +endgame--range (from to)
  "Clock range strings (TSTART TEND) of the days FROM..TO, as day clocktables count them."
  (list (car (org-clock-special-range from nil t))
        (nth 1 (org-clock-special-range to nil t))))

(defun +endgame-area-clocked (area from &optional to)
  "Minutes clocked in AREA's sources on the days FROM..TO (\"YYYY-MM-DD\").
AREA is an area alist or its tag. Nil when the area has no sources."
  (when-let ((sources (+endgame-area-sources area)))
    (pcase-let ((`(,ts ,te) (+endgame--range from (or to from))))
      (apply #'+ (mapcar #'cadr (+endgame--area-tables
                                 sources (list :tstart ts :tend te :maxlevel 1)))))))

;;; Sessions: SPC n j s

(defun +endgame-session-area (&optional pom)
  "The area tag of the session at POM, or nil when it isn't a session.
A session has :ROUTINE: Session routine (inherited) and its area on the
heading itself: :AREA:, or a local tag that is an area's AREA_TAG."
  (org-with-point-at (or pom (point))
    (when (equal (org-entry-get nil "ROUTINE" t) +endgame-session-routine)
      (or (org-entry-get nil "AREA")
          (let ((tags (mapcar (lambda (a) (alist-get 'tag a)) (+endgame-areas))))
            (seq-find (lambda (tg) (member tg tags)) (org-get-tags nil t)))))))

(defun +endgame--session-text (tag stamp)
  "A fresh session for area TAG at STAMP, as a level 1 heading.
The session routine copied the way `SPC n j r' copies it, titled
\"TAG session\", with the area as tag and :AREA:, STAMP after the drawer."
  (let* ((copy (+routines--copy +endgame-session-routine 1))
         (eol (string-match "\n" copy))
         (cookie (and (string-match " \\[[0-9]*/[0-9]*\\]\\'" (substring copy 0 eol))
                      (match-string 0 (substring copy 0 eol))))
         (rest (substring copy (1+ eol)))
         (rest (if (string-match "^:END:\n" rest)
                   (concat (substring rest 0 (match-beginning 0))
                           ":AREA:     " tag "\n:END:\n" stamp "\n"
                           (substring rest (match-end 0)))
                 (concat ":PROPERTIES:\n:ROUTINE:  " +endgame-session-routine
                         "\n:AREA:     " tag "\n:END:\n" stamp "\n" rest))))
    (concat "* TODO " tag " session" (or cookie "") " :" tag ":\n" rest)))

(defun +endgame-session-add (tag stamp &optional ask)
  "Add a session for area TAG at STAMP (an active timestamp, or what org's
date prompt reads, like \"mon 14:00-17:00\"). Returns where it went:
`day' (that day's DO list) or `upcoming' (a future day with no note yet).
A missing day that isn't in the future is made first; ASK lets that ask
the sleep and morning questions."
  (unless (+endgame--area tag) (user-error "No area with AREA_TAG %s" tag))
  (let* ((stamp (if (string-match-p (concat "\\`" org-tsr-regexp "\\'") stamp)
                    stamp
                  (+endgame--stamp stamp)))
         (date (car (+endgame--stamp-range stamp)))
         (text (+endgame--session-text tag stamp))
         (day (+endgame--day-marker date)))
    (cond (day
           (+endgame--append-to-do-list day (list text))
           'day)
          ((string> date (+endgame--today))
           (+endgame--append-to-upcoming text)
           'upcoming)
          (t
           (+endgame--append-to-do-list (+endgame--ensure-day date ask) (list text))
           'day))))

(defun +endgame--read-area ()
  "Pick an area from the areas note; returns its tag."
  (let* ((cands (mapcar (lambda (a)
                          (cons (format "%s (%s)" (alist-get 'name a) (alist-get 'tag a))
                                (alist-get 'tag a)))
                        (+endgame-areas)))
         (pick (completing-read "Area: " cands nil t)))
    (cdr (assoc pick cands))))

(defun +endgame/session (tag stamp)
  "Plan a session: pick an area and a time range (\"14:00-17:00\", \"mon 2pm+3:00\").
It goes into that day's DO list, or into the upcoming note for a future
day that has no note yet (the day's creation moves it in)."
  (interactive
   (list (+endgame--read-area)
         (+endgame--read-stamp "Session (14:00-17:00, mon 2pm+3:00): " nil t)))
  (+endgame--saving
    (message "%s session %s %s" tag stamp
             (if (eq (+endgame-session-add tag stamp t) 'upcoming)
                 "staged in upcoming"
               "added to its day"))))

(defun +endgame-session-json (tag stamp)
  "`+endgame-session-add' for the server: asks nothing, saves, returns JSON.
STAMP is an active timestamp or what org's date prompt reads.
{\"where\": \"day\"|\"upcoming\", \"files\"}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        where)
    (+endgame--saving
      (setq where (+endgame-session-add tag stamp)))
    (+endgame--json `((where . ,(symbol-name where))
                      (files . ,(vconcat (mapcar #'+endgame--relative (reverse +endgame--saved))))))))

(defun +endgame-sessions (from &optional to)
  "Sessions on the days FROM..TO (\"YYYY-MM-DD\"), in the journal and upcoming.
A list of alists: area, date, start, end, minutes, state, title, file,
line. Killed sessions are left out."
  (let ((to (or to from))
        sessions)
    (dolist (file (+endgame--rg-files
                   (format "^[ \t]*:ROUTINE:[ \t]+%s[ \t]*$" (regexp-quote +endgame-session-routine))
                   (list (expand-file-name org-journal-dir) +endgame-upcoming-file)))
      (with-current-buffer (org-get-agenda-file-buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (while (re-search-forward org-heading-regexp nil t)
           (let ((area (and (equal (org-entry-get nil "ROUTINE") +endgame-session-routine)
                            (not (equal (org-get-todo-state) "KILL"))
                            (+endgame-session-area)))
                 (range (+endgame-entry-time-range)))
             (when (and area range
                        (not (string< (car range) from))
                        (not (string> (car range) to)))
               (push `((area . ,area)
                       (date . ,(nth 0 range))
                       (start . ,(nth 1 range))
                       (end . ,(nth 2 range))
                       (minutes . ,(nth 3 range))
                       (state . ,(substring-no-properties (org-get-todo-state)))
                       (title . ,(+endgame--title))
                       (file . ,file)
                       (line . ,(line-number-at-pos (line-beginning-position) t)))
                     sessions)))))))
    (nreverse sessions)))

(defun +endgame-area-planned (area from &optional to sessions)
  "Minutes of AREA's sessions on the days FROM..TO. AREA is an alist or a tag.
SESSIONS, when given, is a `+endgame-sessions' list to count from."
  (let ((tag (if (stringp area) area (alist-get 'tag area))))
    (apply #'+ (mapcar (lambda (s) (or (alist-get 'minutes s) 0))
                       (seq-filter (lambda (s) (equal (alist-get 'area s) tag))
                                   (or sessions (+endgame-sessions from to)))))))

(defun +endgame-areas-report (from &optional to)
  "Planned vs clocked per area for the days FROM..TO: a list of alists.
Keys: tag, name, category, planned and clocked (minutes; clocked is nil
for an area with no SOURCES), baselineWeek, baselineDay."
  (let* ((to (or to from))
         (sessions (+endgame-sessions from to)))
    (mapcar (lambda (a)
              `((tag . ,(alist-get 'tag a))
                (name . ,(alist-get 'name a))
                (category . ,(alist-get 'category a))
                (planned . ,(+endgame-area-planned a from to sessions))
                (clocked . ,(+endgame-area-clocked a from to))
                (baselineWeek . ,(alist-get 'baselineWeek a))
                (baselineDay . ,(alist-get 'baselineDay a))))
            (+endgame-areas))))

(defun +endgame-areas-json ()
  "The areas registry as JSON: `+endgame-areas', plus each area's source files."
  (let ((inhibit-interaction t))
    (+endgame--json
     (vconcat
      (mapcar (lambda (a)
                (append (seq-remove (lambda (kv) (eq (car kv) 'sources)) a)
                        `((sources . ,(vconcat (alist-get 'sources a)))
                          (files . ,(vconcat (delete-dups (mapcar #'car (+endgame-area-sources a))))))))
              (+endgame-areas))))))

(defun +endgame-areas-report-json (from &optional to)
  "`+endgame-areas-report' for FROM..TO (\"YYYY-MM-DD\", nil = org's today) as JSON."
  (let* ((inhibit-interaction t)
         (from (or from (+endgame--today))))
    (+endgame--json `((from . ,from) (to . ,(or to from))
                      (areas . ,(vconcat (+endgame-areas-report from to)))))))

;;; Clocktable per area: #+BEGIN: endgame-areas

(defun +endgame--params-days (params)
  "The days (FROM TO) a clocktable's PARAMS cover, or nil for all time."
  (let* ((block (plist-get params :block))
         (range (if block
                    (org-clock-special-range block nil nil
                                             (plist-get params :wstart) (plist-get params :mstart))
                  (let ((ts (plist-get params :tstart)) (te (plist-get params :tend)))
                    (and ts te (list (org-time-string-to-time ts) (org-time-string-to-time te)))))))
    (when range
      ;; a :block day runs from `org-extend-today-until' to the same hour of
      ;; the next day; the end is exclusive, so the last second before it
      (let ((shift (if block (* 3600 org-extend-today-until) 0)))
        (list (+endgame--date (time-subtract (car range) shift))
              (+endgame--date (time-subtract (nth 1 range) (1+ shift))))))))

(defun org-dblock-write:endgame-areas (params)
  "A clocktable per area of the areas note, from each area's SOURCES.
Takes a clocktable's parameters (:block or :tstart/:tend, :maxlevel,
:fileskip0, …). Each table's caption has the area's planned session time
and its baseline. :skip0 leaves out areas with nothing clocked; areas
without SOURCES are left out."
  (let* ((params (org-combine-plists org-clocktable-defaults '(:maxlevel 2 :fileskip0 t) params))
         (days (+endgame--params-days params))
         (sessions (and days (+endgame-sessions (nth 0 days) (nth 1 days))))
         (block (plist-get params :block))
         (range (if block
                    (org-clock-special-range block nil t (plist-get params :wstart) (plist-get params :mstart))
                  (list (plist-get params :tstart) (plist-get params :tend))))
         (params (org-combine-plists params (list :block nil :tstart (car range) :tend (nth 1 range))))
         (pos (point-marker))
         (first t))
    (set-marker-insertion-type pos t)
    (dolist (area (+endgame-areas))
      (when-let ((sources (+endgame-area-sources area)))
        (let* ((tables (+endgame--area-tables sources params))
               (total (apply #'+ (mapcar #'cadr tables)))
               (week (alist-get 'baselineWeek area))
               (daily (alist-get 'baselineDay area)))
          (unless (and (plist-get params :skip0) (zerop total))
            (goto-char pos)
            (unless first (insert "\n"))
            (setq first nil)
            (org-clocktable-write-default
             (point) tables
             (org-combine-plists
              params
              (list :multifile t
                    :header (concat "#+CAPTION: " (alist-get 'name area)
                                    " :" (alist-get 'tag area) ":"
                                    (if days (format " — planned %s, clocked %s"
                                                     (org-duration-from-minutes
                                                      (+endgame-area-planned area (nth 0 days) (nth 1 days) sessions))
                                                     (org-duration-from-minutes total))
                                      "")
                                    (if week (format ", baseline %s/week" (org-duration-from-minutes week)) "")
                                    (if daily (format ", %s/day" (org-duration-from-minutes daily)) "")
                                    (if block (format " (%s)" block) "")
                                    "\n"))))))))
    (goto-char pos)
    (set-marker pos nil)))

;;; Keys

(when (fboundp 'map!)
  (map! :leader :prefix "n j"
        :desc "Session"        "s" #'+endgame/session
        :desc "Search Forever" "S" #'org-journal-search-forever))

(provide '+endgame-capture)
;;; +endgame-capture.el ends here

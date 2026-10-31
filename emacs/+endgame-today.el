;;; +endgame-today.el --- the today list and the today panel -*- lexical-binding: t; -*-

;;; Commentary:
;; The endgame's "today": every item due on a day, as data, and the views on it.
;; Designed in the vault note "the endgame: org vault as the brain, thin clients
;; for everything else" (id 9b510b89-c57e-40d3-b5b3-7807cd49e469).
;;
;; - `+endgame-today-items' / `+endgame-today-json': the today list for a date.
;;   Tasks scheduled, due or overdue in their homes (straight from
;;   `org-agenda-list', so the agenda files, skip settings and
;;   `org-extend-today-until' are the agenda's own), APPTs, the day's own items
;;   (routine, habit and session copies in the daily note's DO list) and items
;;   staged for that day in the upcoming note. Timed first by time, untimed
;;   below, one done counter. The JSON is what vault-api serves the phone.
;; - `+endgame/today-agenda' (SPC o a d): the cheap version, a block agenda.
;; - `+endgame/today-panel' (SPC o t): a workspace with three windows: the
;;   org-timeblock timeline on the left, a dashboard on the right (the list
;;   with checkboxes, habits with this week's heatmap, today's clocked time,
;;   planned vs actual per area) and the real daily note under it, narrowed to
;;   the day. The panel shows, it doesn't own: everything is read from the
;;   vault on each refresh, and every line leads to an action on the heading.
;;
;; It leans on the literate Doom config when it's there (`my/org-fast-scan',
;; `my/org-roam-refresh-agenda-files', the `+habits-heatmap-*' code) and on
;; the capture module's `+endgame-areas-report' for planned vs actual, and works
;; without them, which is how the tests run.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'calendar)
(require 'org)
(require 'org-agenda)
(require 'org-element)
(require 'org-id)

(defvar text-scale-mode-step)
(defvar text-scale-mode-amount)
(defvar +endgame-today-note-mode)
(defvar +endgame-today-note--day)
(defvar +endgame-today-note--header)

(defgroup +endgame-today nil
  "The today list and the today panel."
  :group 'org)

(defcustom +endgame-today-refresh-interval 60
  "Seconds between refreshes of a visible dashboard, for the clock and the date."
  :type 'integer)

(defcustom +endgame-today-workspace "today"
  "Name of the workspace (or tab) the today panel opens in."
  :type 'string)

(defcustom +endgame-today-timeline-width 0.38
  "Share of the frame's width the timeline gets."
  :type 'number)

(defcustom +endgame-today-note-height 0.45
  "Share of the right column's height the daily note gets."
  :type 'number)

(defcustom +endgame-today-text-scale -1
  "Text zoom of the panel's three windows, in `text-scale-mode' steps.
Negative is smaller, so more fits. Each window can still be zoomed on
its own with C-x C-- / C-x C-= / C-x C-0; the timeline redraws itself
at its new size."
  :type 'integer)

(defcustom +endgame-today-note-search-days 31
  "How many days H / L in the panel's note look for the next daily note."
  :type 'integer)

(defcustom +endgame-today-save-after-change t
  "Non-nil means a state change from the dashboard saves the heading's file.
The phone and the server read the files: an unsaved tick is invisible to them."
  :type 'boolean)

(defcustom +endgame-today-clocked-rows 6
  "Headings listed under the clocked time, the longest first."
  :type 'integer)

(defvar +endgame-today-dashboard-buffer "*today*"
  "Name of the dashboard buffer.")

(defconst +endgame-today--agenda-buffer " *endgame-today-agenda*"
  "The hidden agenda the today list is read from; killed after every build.")

;;;; Dates

(defun +endgame-today--abs (date)
  "Absolute day of DATE, a YYYY-MM-DD string or nil for org's today."
  (if (null date)
      (org-today)
    (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number (split-string date "-"))))
      (calendar-absolute-from-gregorian (list m d y)))))

(defun +endgame-today--date (abs)
  "YYYY-MM-DD of absolute day ABS."
  (pcase-let ((`(,m ,d ,y) (calendar-gregorian-from-absolute abs)))
    (format "%04d-%02d-%02d" y m d)))

(defun +endgame-today--time (abs &optional minutes)
  "Emacs time of absolute day ABS, MINUTES after midnight (default noon)."
  (pcase-let ((`(,m ,d ,y) (calendar-gregorian-from-absolute abs)))
    (let ((min (or minutes 720)))
      (encode-time 0 (% min 60) (/ min 60) d m y))))

(defun +endgame-today--hhmm (minutes)
  "MINUTES after midnight as HH:MM."
  (and minutes (format "%02d:%02d" (/ minutes 60) (% minutes 60))))

(defun +endgame-today--duration (minutes)
  "MINUTES as H:MM."
  (format "%d:%02d" (/ minutes 60) (% minutes 60)))

;;;; Vault files

(defun +endgame-today--vault-file (rel)
  "Absolute path of REL, a path inside the vault (`org-directory')."
  (expand-file-name rel org-directory))

(defun +endgame-today--upcoming-file ()
  "The staging note: future day-own items wait there for their day."
  (or (bound-and-true-p +endgame-upcoming-file)
      (+endgame-today--vault-file "roam/20261031030202-upcoming.org")))

(defun +endgame-today--areas-file ()
  "The area registry."
  (or (bound-and-true-p +endgame-areas-file)
      (+endgame-today--vault-file "roam/20261031030150-areas.org")))

(defun +endgame-today--life-file ()
  "The life note: Appointments and Errands."
  (or (bound-and-true-p +endgame-life-file)
      (+endgame-today--vault-file "roam/20261031024752-life.org")))

(defun +endgame-today--rel (file)
  "FILE relative to the vault, the way vault-api names notes."
  (let ((root (file-truename (expand-file-name org-directory)))
        (true (file-truename file)))
    (if (string-prefix-p root true)
        (file-relative-name true root)
      (abbreviate-file-name file))))

(defun +endgame-today--buffer (file)
  "A buffer visiting FILE, opened the way the agenda opens its files.
That's cheap: no per-file mode hooks (see the config's
`my/org-agenda-delay-mode-hooks-a'), and the real setup runs when the
buffer is first shown."
  (or (org-find-base-buffer-visiting file)
      (let ((org-inhibit-startup t))
        (org-get-agenda-file-buffer file))))

(defun +endgame-today--day-file (abs)
  "The weekly journal file that holds day ABS."
  (let ((time (+endgame-today--time abs)))
    (if (and (require 'org-journal nil t) (fboundp 'org-journal--get-entry-path)
             (boundp 'org-journal-file-format))
        (org-journal--get-entry-path time)
      ;; org-journal names a weekly file after the week's Monday
      (let* ((dow (calendar-day-of-week (calendar-gregorian-from-absolute abs)))
             (monday (- abs (mod (+ dow 6) 7))))
        (expand-file-name
         (format-time-string (or (bound-and-true-p org-journal-file-format) "week%V-%Y-%m-%d.org")
                             (+endgame-today--time monday))
         (or (bound-and-true-p org-journal-dir)
             (+endgame-today--vault-file "roam/daily/")))))))

(defun +endgame-today--day-marker (abs)
  "Marker at day ABS's heading in its weekly journal file, or nil."
  (let ((file (+endgame-today--day-file abs))
        (date (+endgame-today--date abs)))
    (when (file-exists-p file)
      (with-current-buffer (+endgame-today--buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (when (re-search-forward
                (format "^\\* .*[^0-9]%s\\(?:[^0-9]\\|$\\)" (regexp-quote date)) nil t)
           (copy-marker (line-beginning-position))))))))

;;;; Reading a heading

(defconst +endgame-today--cookie-re "[ \t]*\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]"
  "A statistics cookie in a heading.")

(defconst +endgame-today--tag-token-re "[ \t]+\\(:[[:alnum:]_@#%:]+:\\)\\(?:[ \t]\\|$\\)"
  "A :tag: written inside a heading's title, where org doesn't see it as a tag.")

(defun +endgame-today--heading-parts ()
  "Title, progress cookie and stray title tags of the heading at point.
Links show as their description, timestamps and the cookie are dropped."
  (let* ((raw (org-link-display-format (substring-no-properties (org-get-heading t t t t))))
         (progress (and (string-match "\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]" raw) (match-string 0 raw)))
         (title raw)
         stray)
    (while (string-match +endgame-today--tag-token-re title)
      (setq stray (append stray (split-string (match-string 1 title) ":" t))
            title (replace-match " " t t title)))
    (setq title (replace-regexp-in-string +endgame-today--cookie-re "" title))
    (setq title (replace-regexp-in-string (concat "[ \t]*" org-ts-regexp-both) "" title))
    (list (string-trim (replace-regexp-in-string "[ \t]+" " " title)) progress stray)))

(defun +endgame-today--stamps ()
  "Active timestamps in the entry at point (heading and body, not children).
Property and keyword lines don't count, like the agenda file scan."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (save-excursion (outline-next-heading) (point)))
          out)
      (while (re-search-forward org-ts-regexp end t)
        (let ((beg (match-beginning 0)))
          (unless (save-excursion
                    (beginning-of-line)
                    (looking-at-p "[ \t]*\\(?::[^: \t\n]+:\\|#\\+\\)"))
            (save-excursion
              (goto-char beg)
              (let ((ts (org-element-timestamp-parser)))
                (when ts
                  (push ts out)
                  (goto-char (org-element-property :end ts))))))))
      (nreverse out))))

(defun +endgame-today--stamp-abs (ts &optional end)
  "Absolute day TS starts (or with END, ends) on."
  (calendar-absolute-from-gregorian
   (if end
       (list (org-element-property :month-end ts) (org-element-property :day-end ts)
             (org-element-property :year-end ts))
     (list (org-element-property :month-start ts) (org-element-property :day-start ts)
           (org-element-property :year-start ts)))))

(defun +endgame-today--stamp-on-p (ts abs)
  "Non-nil if timestamp TS falls on day ABS (its own day, or inside its range)."
  (<= (+endgame-today--stamp-abs ts) abs (+endgame-today--stamp-abs ts t)))

(defun +endgame-today--stamp-times (ts)
  "(START . END) minutes of timestamp TS, nil when it has no time."
  (let ((h (org-element-property :hour-start ts)))
    (when h
      (let* ((start (+ (* 60 h) (or (org-element-property :minute-start ts) 0)))
             (he (org-element-property :hour-end ts))
             (end (and he (+ (* 60 he) (or (org-element-property :minute-end ts) 0)))))
        (cons start (and end (/= end start) end))))))

(defun +endgame-today--entry-on (abs)
  "Non-nil when the entry at point has an active timestamp on day ABS.
The value is (START . END) minutes of the first timed one, or t."
  (let ((on (seq-filter (lambda (ts) (+endgame-today--stamp-on-p ts abs))
                        (+endgame-today--stamps))))
    (and on (or (seq-some #'+endgame-today--stamp-times on) t))))

;;;; Areas

(defvar +endgame-today--areas-cache nil
  "(FILE TICK . AREAS) of the last registry read.")

(defun +endgame-today-areas ()
  "The areas in the registry, in file order: alists of tag, name, category.
Uses the capture module's `+endgame-areas' when it's loaded."
  (if (fboundp '+endgame-areas)
      (+endgame-areas)
    (let ((file (+endgame-today--areas-file)))
      (when (file-exists-p file)
        (with-current-buffer (+endgame-today--buffer file)
          (let ((tick (buffer-chars-modified-tick)))
            (unless (and (equal (car +endgame-today--areas-cache) file)
                         (eq (cadr +endgame-today--areas-cache) tick))
              (setq +endgame-today--areas-cache
                    (cons file
                          (cons tick
                                (org-with-wide-buffer
                                 (delq nil
                                       (org-map-entries
                                        (lambda ()
                                          (let ((tag (org-entry-get nil "AREA_TAG")))
                                            (when (and tag (not (string-empty-p tag)))
                                              `((tag . ,tag)
                                                (name . ,(org-get-heading t t t t))
                                                (category . ,(save-excursion
                                                               (and (org-up-heading-safe)
                                                                    (org-get-heading t t t t))))))))
                                        "LEVEL=2")))))))
            (cddr +endgame-today--areas-cache)))))))

(defun +endgame-today--area (tags)
  "Area of the heading at point: its :AREA:, or the first of TAGS that's an area."
  (or (+endgame-today--prop "AREA")
      (let ((areas (mapcar (lambda (a) (alist-get 'tag a)) (+endgame-today-areas))))
        (seq-find (lambda (tag) (member tag areas)) tags))))

;;;; The today list

(defun +endgame-today--prop (name)
  "Property NAME of the heading at point, its own, not inherited.
Also read from a drawer org doesn't see because a line sits between it
and the heading (a session's timestamp, written above its drawer)."
  (or (org-entry-get nil name)
      (save-excursion
        (org-back-to-heading t)
        (let ((end (save-excursion (outline-next-heading) (point))))
          (and (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" end t)
               (let ((dend (save-excursion (re-search-forward "^[ \t]*:END:[ \t]*$" end t))))
                 (and dend
                      (re-search-forward (format "^[ \t]*:%s:[ \t]+\\(.*?\\)[ \t]*$" (regexp-quote name))
                                         dend t)
                      (match-string-no-properties 1))))))))

(defun +endgame-today--kind (state)
  "What the heading at point is, for the today list, given its todo STATE."
  (let ((routine (+endgame-today--prop "ROUTINE")))
    (cond ((+endgame-today--prop "HABIT_ID") 'habit)
          ((equal routine "Session routine") 'session)
          (routine 'routine)
          ((or (equal state "APPT") (null state)) 'appt)
          (t 'task))))

(defun +endgame-today--item (abs &optional seen)
  "The heading at point as a today-list item for day ABS.
SEEN is what the agenda said about it: a plist of :type :time :end
:extra, or nil when the heading was found in the daily note or staging."
  (org-back-to-heading t)
  (pcase-let* ((state (org-get-todo-state))
               (`(,title ,progress ,stray) (+endgame-today--heading-parts))
               (tags (append (mapcar #'substring-no-properties (org-get-tags nil t)) stray))
               (type (plist-get seen :type))
               (extra (replace-regexp-in-string
                       "[ \t]+" " " (string-trim (or (plist-get seen :extra) ""))))
               ;; a rollover sits on today without its old day's time
               (late (and (member type '("past-scheduled" "deadline" "closed"))
                          (plist-get seen :late)))
               (own (+endgame-today--entry-on abs))
               (times (cond ((and seen (not late) (not (equal type "closed")) (plist-get seen :time))
                             (cons (plist-get seen :time) (plist-get seen :end)))
                            ((consp own) own)))
               (file (buffer-file-name (buffer-base-buffer)))
               (id (org-entry-get nil "ID")))
    `((ref . ,(or id (format "%s:%d" (+endgame-today--rel file) (line-number-at-pos nil t))))
      (id . ,id)
      (title . ,title)
      (state . ,state)
      (done . ,(and state (member state org-done-keywords) t))
      (kind . ,(+endgame-today--kind state))
      (start . ,(car times))
      (end . ,(cdr times))
      (tags . ,(delete-dups tags))
      (area . ,(+endgame-today--area tags))
      (file . ,(+endgame-today--rel file))
      (line . ,(line-number-at-pos nil t))
      (progress . ,progress)
      (rollover . ,(and (string-match "Sched\\.[ \t]*\\([0-9]+\\)x" extra)
                        (string-to-number (match-string 1 extra))))
      (overdue . ,(and (string-match "\\([0-9]+\\) d\\. ago" extra)
                       (string-to-number (match-string 1 extra))))
      ;; org's leader when it says more than "Scheduled:"
      (agenda . ,(and (not (string-empty-p extra)) (not (equal type "closed"))
                      (not (equal extra (string-trim (car org-agenda-scheduled-leaders))))
                      extra))
      (checkable . ,(and state t))
      (marker . ,(point-marker)))))

(defun +endgame-today--agenda-lines (abs)
  "What `org-agenda-list' shows on day ABS: (MARKER . PLIST) per line.
The build is the agenda's own, with the closed log on so the day's
finished tasks are there too. Its buffer is hidden and killed after."
  (let ((org-agenda-buffer-tmp-name +endgame-today--agenda-buffer)
        (org-agenda-buffer-name +endgame-today--agenda-buffer)
        (org-agenda-buffer nil)
        (org-agenda-contributing-files nil)
        (org-agenda-sticky nil)
        (org-agenda-start-on-weekday nil)
        ;; `org-agenda-mode' resets the log from its start value
        (org-agenda-start-with-log-mode '(closed))
        (org-agenda-show-log '(closed))
        (org-agenda-use-time-grid nil)    ; grid lines are no items
        (org-agenda-window-setup 'current-window)
        (org-agenda-restore-windows-after-quit nil)
        (org-agenda-finalize-hook nil)
        (inhibit-message t)
        lines)
    (when (fboundp 'my/org-roam-refresh-agenda-files)
      (my/org-roam-refresh-agenda-files))
    (save-window-excursion
      (if (fboundp 'my/org-fast-scan)
          (my/org-fast-scan #'org-agenda-list nil abs 1)
        (let ((org-mode-hook nil) (org-inhibit-startup t))
          (org-agenda-list nil abs 1))))
    (let ((buf (get-buffer +endgame-today--agenda-buffer)))
      (unwind-protect
          (with-current-buffer buf
            (goto-char (point-min))
            (while (not (eobp))
              (let ((m (get-text-property (point) 'org-hd-marker))
                    (type (get-text-property (point) 'type)))
                (when (and m (marker-buffer m) type)
                  (let* ((tod (get-text-property (point) 'time-of-day))
                         (dur (get-text-property (point) 'duration))
                         (ts (get-text-property (point) 'ts-date))
                         (start (and (integerp tod) (+ (* 60 (/ tod 100)) (% tod 100)))))
                    (push (cons (copy-marker m)
                                (list :type type
                                      :time start
                                      :end (and start (numberp dur) (> dur 0) (+ start (round dur)))
                                      :extra (get-text-property (point) 'extra)
                                      :late (and (integerp ts) (< ts abs))))
                          lines))))
              (forward-line 1)))
        (when (buffer-live-p buf) (kill-buffer buf))))
    (nreverse lines)))

(defun +endgame-today--planned-p (abs)
  "Non-nil if the entry at point was planned for day ABS or earlier.
For a task closed that day: it was on the list only if it had a date by then."
  (or (seq-some (lambda (f) (let ((s (funcall f (point))))
                              (and s (<= (time-to-days s) abs))))
                '(org-get-scheduled-time org-get-deadline-time))
      (+endgame-today--entry-on abs)))

(defun +endgame-today--day-own-markers (abs)
  "Markers at the day-own items of day ABS: its DO list, and staged ones.
The DO list's direct children with a todo keyword, and top-level
headings of the upcoming note with an active timestamp on that day."
  (let (out)
    (let ((day (+endgame-today--day-marker abs)))
      (when day
        (with-current-buffer (marker-buffer day)
          (org-with-wide-buffer
           (goto-char day)
           (let* ((level (org-current-level))
                  (end (save-excursion (org-end-of-subtree t t))))
             (when (re-search-forward (format "^\\*\\{%d\\} DO list\\b" (1+ level)) end t)
               (let ((do-end (save-excursion (org-end-of-subtree t t)))
                     (re (format "^\\*\\{%d\\} " (+ level 2))))
                 (while (re-search-forward re do-end t)
                   (when (org-get-todo-state)
                     (push (copy-marker (line-beginning-position)) out))))))))
        (set-marker day nil)))
    (let ((file (+endgame-today--upcoming-file)))
      (when (file-exists-p file)
        (with-current-buffer (+endgame-today--buffer file)
          (org-with-wide-buffer
           (goto-char (point-min))
           (while (re-search-forward "^\\* " nil t)
             (when (+endgame-today--entry-on abs)
               (push (copy-marker (line-beginning-position)) out)))))))
    (nreverse out)))

(defun +endgame-today--sort (items)
  "ITEMS timed first by start time, then untimed, open before done."
  (let ((timed (seq-filter (lambda (i) (alist-get 'start i)) items))
        (untimed (seq-remove (lambda (i) (alist-get 'start i)) items)))
    (append (sort timed (lambda (a b) (< (alist-get 'start a) (alist-get 'start b))))
            (seq-remove (lambda (i) (alist-get 'done i)) untimed)
            (seq-filter (lambda (i) (alist-get 'done i)) untimed))))

(defun +endgame-today-items (&optional date)
  "The today list for DATE (YYYY-MM-DD, nil for org's today), as data.
An alist: date, items, ahead (deadline warnings, not due yet) and
counts (done, total: the checkable items). Each item is an alist of
ref, id, title, state, done, kind (appt session routine habit task),
start and end (minutes or nil), tags, area, file (relative to the
vault), line, progress, rollover (org's Sched. Nx), overdue (days
past a deadline), agenda (org's own leader text), checkable and marker."
  (let* ((abs (+endgame-today--abs date))
         (seen (make-hash-table :test #'equal))
         items ahead)
    (cl-flet ((key (m) (cons (marker-buffer m) (marker-position m)))
              (add (m plist)
                (with-current-buffer (marker-buffer m)
                  (org-with-wide-buffer
                   (goto-char m)
                   (push (+endgame-today--item abs plist) items)))))
      (dolist (line (+endgame-today--agenda-lines abs))
        (pcase-let* ((`(,m . ,plist) line)
                     (type (plist-get plist :type))
                     (k (key m)))
          (cond
           ((gethash k seen))
           ((equal type "upcoming-deadline")
            (with-current-buffer (marker-buffer m)
              (org-with-wide-buffer
               (goto-char m)
               (push (+endgame-today--item abs plist) ahead))))
           ((and (equal type "closed")
                 (not (with-current-buffer (marker-buffer m)
                        (org-with-wide-buffer (goto-char m) (+endgame-today--planned-p abs))))))
           (t (puthash k t seen) (add m plist)))
          (set-marker m nil)))
      (dolist (m (+endgame-today--day-own-markers abs))
        (unless (gethash (key m) seen)
          (puthash (key m) t seen)
          (add m nil))
        (set-marker m nil)))
    (let* ((items (+endgame-today--sort (nreverse items)))
           (checkable (seq-filter (lambda (i) (alist-get 'checkable i)) items)))
      `((date . ,(+endgame-today--date abs))
        (items . ,items)
        (ahead . ,(nreverse ahead))
        (counts . ((done . ,(seq-count (lambda (i) (alist-get 'done i)) checkable))
                   (total . ,(length checkable))))))))

;;;; JSON for the server

(defun +endgame-today--revert ()
  "Bring unmodified org buffers in line with disk.
Syncthing and vault-api write the files under them."
  (if (fboundp 'vault-agenda--revert)
      (vault-agenda--revert)
    (dolist (buf (buffer-list))
      (let ((file (buffer-file-name buf)))
        (when (and file (string-suffix-p ".org" file) (not (buffer-modified-p buf)))
          (cond ((not (file-exists-p file)) (kill-buffer buf))
                ((not (verify-visited-file-modtime buf))
                 (with-current-buffer buf
                   (let ((org-mode-hook nil) (org-inhibit-startup t))
                     (revert-buffer t t))))))))))

(defun +endgame-today--json-item (item)
  "ITEM ready for `json-encode': times as HH:MM, false for nil flags, no marker."
  (let ((bool (lambda (v) (if v t :json-false))))
    `((ref . ,(alist-get 'ref item))
      (id . ,(alist-get 'id item))
      (title . ,(alist-get 'title item))
      (state . ,(alist-get 'state item))
      (done . ,(funcall bool (alist-get 'done item)))
      (kind . ,(symbol-name (alist-get 'kind item)))
      (start . ,(+endgame-today--hhmm (alist-get 'start item)))
      (end . ,(+endgame-today--hhmm (alist-get 'end item)))
      (tags . ,(vconcat (alist-get 'tags item)))
      (area . ,(alist-get 'area item))
      (file . ,(alist-get 'file item))
      (line . ,(alist-get 'line item))
      (progress . ,(alist-get 'progress item))
      (rollover . ,(alist-get 'rollover item))
      (overdue . ,(alist-get 'overdue item))
      (agenda . ,(alist-get 'agenda item))
      (checkable . ,(funcall bool (alist-get 'checkable item))))))

(defun +endgame-today--json-time (time)
  "TIME as HH:MM, or nil."
  (and time (format-time-string "%H:%M" time)))

(defun +endgame-today-json (&optional date)
  "The today list for DATE (YYYY-MM-DD, nil for org's today) as a JSON string.
For vault-api, through emacsclient: never prompts, changes nothing.
  {date, today, week: {number, year, file, priority},
   items: [{ref id title state done kind start end tags area file line
            progress rollover overdue agenda checkable}],
   ahead: [items], counts: {done, total},
   clocking: {title, since, minutes} | null,
   next: {item fields..., in} | null,
   inbox_count, watch_out: {inbox, deadlines: [items], rollovers: [items]},
   clocked: {total, headings: [{title, note, minutes, running}]}}
start/end/since are HH:MM or null; minutes are integers; ref is the
:ID:, or file:line without one; next's in is minutes until it starts,
negative once it has."
  (let ((inhibit-interaction t))
    (+endgame-today--revert)
    (let* ((data (+endgame-today-data date))
           (items (lambda (key alist) (vconcat (mapcar #'+endgame-today--json-item (alist-get key alist)))))
           (clocking (alist-get 'clocking data))
           (next (alist-get 'next data))
           (clocked (alist-get 'clocked data))
           (watch (alist-get 'watch-out data))
           (json-encoding-pretty-print nil))
      (json-encode
       `((date . ,(alist-get 'date data))
         (today . ,(+endgame-today--date (org-today)))
         (week . ,(alist-get 'week data))
         (items . ,(funcall items 'items data))
         (ahead . ,(funcall items 'ahead data))
         (counts . ,(alist-get 'counts data))
         (clocking . ,(and clocking
                           `((title . ,(alist-get 'title clocking))
                             (since . ,(+endgame-today--json-time (alist-get 'since clocking)))
                             (minutes . ,(alist-get 'minutes clocking)))))
         (next . ,(and next (append (+endgame-today--json-item next)
                                    `((in . ,(alist-get 'in next))))))
         (inbox_count . ,(alist-get 'inbox data))
         (watch_out . ((inbox . ,(alist-get 'inbox watch))
                       (deadlines . ,(funcall items 'deadlines watch))
                       (rollovers . ,(funcall items 'rollovers watch))))
         (clocked . ((total . ,(alist-get 'total clocked))
                     (headings . ,(vconcat
                                   (mapcar (lambda (r)
                                             `((title . ,(alist-get 'title r))
                                               (note . ,(alist-get 'note r))
                                               (minutes . ,(alist-get 'minutes r))
                                               (running . ,(if (alist-get 'running r) t :json-false))))
                                           (alist-get 'headings clocked)))))))))))

;;;; The block agenda (the cheap version)

(defun +endgame-today--skip-unless-day-own ()
  "Agenda skip function: keep today's DO list items that have no date today.
Those are the day's own items the agenda block above can't see."
  (let ((next (save-excursion (or (outline-next-heading) (point-max))))
        (date (+endgame-today--date (org-today))))
    (unless (and (save-excursion
                   (and (org-up-heading-safe)
                        (looking-at-p "\\*+ DO list\\b")
                        (org-up-heading-safe)
                        (= (org-current-level) 1)
                        (string-match-p (regexp-quote date) (org-get-heading t t t t))))
                 (not (+endgame-today--entry-on (org-today)))
                 (not (org-get-scheduled-time (point)))
                 (not (org-get-deadline-time (point))))
      next)))

(defun +endgame-today--agenda-command ()
  "The today list as a block agenda, for `org-agenda-custom-commands'."
  '("d" "Today list"
    ((agenda ""
             ((org-agenda-span 1)
              (org-agenda-start-day nil)
              (org-agenda-start-with-log-mode '(closed))
              (org-agenda-overriding-header "Today")))
     (todo ""
           ((org-agenda-files (list (+endgame-today--day-file (org-today))))
            (org-agenda-skip-function #'+endgame-today--skip-unless-day-own)
            (org-agenda-overriding-header "Day's own, no time"))))))

(with-eval-after-load 'org
  (setq org-agenda-custom-commands
        (append (seq-remove (lambda (c) (equal (car c) "d")) org-agenda-custom-commands)
                (list (+endgame-today--agenda-command)))))

(defun +endgame/today-agenda ()
  "The today list as a block agenda.
Today's agenda, then the day's own items that have no date."
  (interactive)
  (org-agenda nil "d"))

;;;; Dashboard data: habits, clock, areas

(defun +endgame-today--habit-week ()
  "This week's habit heatmap, or nil without the config's heatmap code."
  (when (fboundp '+habits-heatmap-data)
    (ignore-errors (+habits-heatmap-data 1))))

(defun +endgame-today--clock-window (abs)
  "(START . END) of org's day ABS as Emacs times.
It starts at `org-extend-today-until' and ends at that hour the next day."
  (let ((shift (* 60 (or org-extend-today-until 0))))
    (cons (+endgame-today--time abs shift)
          (+endgame-today--time (1+ abs) shift))))

(defun +endgame-today--clock-files (abs)
  "Vault files with a CLOCK line that may touch day ABS, plus modified org buffers."
  (let* ((rg (executable-find "rg"))
         (dates (mapcar #'+endgame-today--date (list (1- abs) abs (1+ abs))))
         (files (when rg
                  (with-temp-buffer
                    (apply #'call-process rg nil t nil
                           "--files-with-matches" "--no-messages" "--glob" "*.org"
                           "--glob" "!**/templates/**" "--glob" "!**/config/**"
                           (append
                            (list "-e" (format "CLOCK: \\[(%s)" (string-join dates "|")))
                            (list (expand-file-name (or (bound-and-true-p my/org-agenda-root)
                                                        org-directory)))))
                    (split-string (buffer-string) "\n" t)))))
    (delete-dups
     (append files
             (delq nil (mapcar (lambda (b) (and (buffer-modified-p b)
                                                 (with-current-buffer b (derived-mode-p 'org-mode))
                                                 (buffer-file-name b)))
                               (buffer-list)))
             (unless rg (org-agenda-files))))))

(defun +endgame-today-clocked (&optional date)
  "Time clocked on DATE (YYYY-MM-DD, nil for today), from every CLOCK line.
The day is org's day, so with `org-extend-today-until' 5 it runs from
05:00 to 05:00. A running clock counts up to now. Returns an alist:
total (minutes), running (title or nil) and since (when that clock
started), and headings: a list of alists of title, note, minutes,
running, marker, longest first."
  (let* ((abs (+endgame-today--abs date))
         (window (+endgame-today--clock-window abs))
         (now (current-time))
         (by (make-hash-table :test #'equal))
         (total 0) running)
    (dolist (file (+endgame-today--clock-files abs))
      (when (file-exists-p file)
        (with-current-buffer (+endgame-today--buffer file)
          (org-with-wide-buffer
           (goto-char (point-min))
           (while (re-search-forward
                   "^[ \t]*CLOCK: \\(\\[[^]]+\\]\\)\\(?:--\\(\\[[^]]+\\]\\)\\)?" nil t)
             (let* ((from-s (match-string 1))
                    (to-s (match-string 2))
                    (start (org-time-string-to-time from-s))
                    (open (not to-s))
                    (end (if open now (org-time-string-to-time to-s)))
                    (from (if (time-less-p start (car window)) (car window) start))
                    (to (if (time-less-p (cdr window) end) (cdr window) end))
                    (min (/ (float-time (time-subtract to from)) 60)))
               (when (> min 0)
                 (save-excursion
                   (org-back-to-heading t)
                   (let* ((k (cons (current-buffer) (point)))
                          (row (or (gethash k by)
                                   (puthash k (list :title (car (+endgame-today--heading-parts))
                                                    :note (or (org-get-title) (file-name-base file))
                                                    :minutes 0 :marker (point-marker))
                                            by))))
                     (plist-put row :minutes (+ (plist-get row :minutes) min))
                     (when open
                       (plist-put row :running start)
                       (setq running row)))))))))))
    (let (rows)
      (maphash (lambda (_ row)
                 (setq total (+ total (plist-get row :minutes)))
                 (push `((title . ,(plist-get row :title))
                         (note . ,(plist-get row :note))
                         (minutes . ,(round (plist-get row :minutes)))
                         (running . ,(and (plist-get row :running) t))
                         (marker . ,(plist-get row :marker)))
                       rows))
               by)
      `((total . ,(round total))
        (running . ,(and running (plist-get running :title)))
        (since . ,(and running (plist-get running :running)))
        (headings . ,(sort rows (lambda (a b) (> (alist-get 'minutes a) (alist-get 'minutes b)))))))))

(defun +endgame-today-area-time (&optional date items)
  "Planned vs clocked minutes per area on DATE, in registry order.
From the capture module's `+endgame-areas-report' when it's loaded: per
area tag, name, category, planned, clocked (nil for an area with no
SOURCES), baselineWeek, baselineDay. Without it, planned is summed here
from the sessions in ITEMS (the today list) and clocked is nil."
  (let ((date (or date (+endgame-today--date (org-today)))))
    (if (fboundp '+endgame-areas-report)
        (+endgame-areas-report date)
      (let ((items (or items (alist-get 'items (+endgame-today-items date)))))
        (mapcar
         (lambda (area)
           (let ((tag (alist-get 'tag area)))
             `((tag . ,tag)
               (name . ,(alist-get 'name area))
               (category . ,(alist-get 'category area))
               (planned . ,(apply #'+ (mapcar (lambda (i)
                                                (if (and (eq (alist-get 'kind i) 'session)
                                                         (equal (alist-get 'area i) tag)
                                                         (alist-get 'start i) (alist-get 'end i))
                                                    (- (alist-get 'end i) (alist-get 'start i))
                                                  0))
                                              items)))
               (clocked . nil))))
         (+endgame-today-areas))))))

;;;; The day around the list: header, now, watch out

(defvar org-clock-start-time)
(defvar org-clock-marker)

(defcustom +endgame-today-rollover-limit 3
  "Rollovers (org's Sched. Nx) from which a task is an offender to decide on."
  :type 'integer)

(defun +endgame-today--inbox-file ()
  "The inbox note: captures wait there until they're processed."
  (or (bound-and-true-p +endgame-inbox-file)
      (+endgame-today--vault-file "roam/20261031024803-inbox.org")))

(defun +endgame-today-inbox-count ()
  "Open top-level tasks in the inbox note."
  (let ((file (+endgame-today--inbox-file)))
    (if (not (file-exists-p file))
        0
      (with-current-buffer (+endgame-today--buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (let ((n 0))
           (while (re-search-forward "^\\* " nil t)
             (when (member (org-get-todo-state) org-not-done-keywords)
               (setq n (1+ n))))
           n))))))

(defun +endgame-today--priority (file)
  "The weekly priority in weekly journal FILE, or nil.
It's a paragraph in the root of the weekly note: the first prose above
the first day, past the drawer, keywords and the week's clocktable."
  (when (file-exists-p file)
    (with-current-buffer (+endgame-today--buffer file)
      (org-with-wide-buffer
       (goto-char (point-min))
       (let ((stop (save-excursion (if (re-search-forward "^\\* " nil t) (match-beginning 0) (point-max))))
             (skip nil)
             para)
         (while (and (< (point) stop) (not (and para (looking-at-p "[ \t]*$"))))
           (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position)))
                 (case-fold-search t))
             (cond (skip (when (string-match-p skip line) (setq skip nil)))
                   ((string-match-p "^[ \t]*:[A-Za-z_]+:[ \t]*$" line) (setq skip "^[ \t]*:END:"))
                   ((string-match-p "^[ \t]*#\\+BEGIN" line) (setq skip "^[ \t]*#\\+END"))
                   ((string-match-p "^[ \t]*\\(?:#\\|$\\||\\)" line))
                   (t (push (string-trim line) para))))
           (forward-line 1))
         (and para (org-link-display-format (string-join (nreverse para) " "))))))))

(defun +endgame-today-week (abs)
  "Day ABS's week: ISO number and year, the weekly note, its priority."
  (let ((time (+endgame-today--time abs))
        (file (+endgame-today--day-file abs)))
    `((number . ,(string-to-number (format-time-string "%V" time)))
      (year . ,(string-to-number (format-time-string "%G" time)))
      (file . ,(and (file-exists-p file) (+endgame-today--rel file)))
      (priority . ,(+endgame-today--priority file)))))

(defun +endgame-today--now-minutes (abs)
  "Minutes from the midnight that starts day ABS to now.
Past 24:00 after midnight, while org's day is still ABS."
  (floor (float-time (time-subtract nil (+endgame-today--time abs 0))) 60))

(defun +endgame-today-now (abs items clocked)
  "What's going on on day ABS: (CLOCKING . NEXT).
CLOCKING is the running clock (Emacs's own, else an open CLOCK line in
CLOCKED, from `+endgame-today-clocked'): title, since, minutes, marker.
NEXT is the first open timed item in ITEMS that hasn't ended, with in:
minutes until it starts, negative when it already has. Only for today."
  (let ((clocking
         (cond ((and (fboundp 'org-clocking-p) (org-clocking-p))
                (with-current-buffer (marker-buffer org-clock-marker)
                  (org-with-wide-buffer
                   (goto-char org-clock-marker)
                   `((title . ,(car (+endgame-today--heading-parts)))
                     (since . ,org-clock-start-time)
                     (minutes . ,(floor (float-time (time-subtract nil org-clock-start-time)) 60))
                     (marker . ,(copy-marker org-clock-marker))))))
               ((alist-get 'running clocked)
                (let ((row (seq-find (lambda (r) (alist-get 'running r)) (alist-get 'headings clocked))))
                  `((title . ,(alist-get 'running clocked))
                    (since . ,(alist-get 'since clocked))
                    (minutes . ,(floor (float-time (time-subtract nil (alist-get 'since clocked))) 60))
                    (marker . ,(alist-get 'marker row)))))))
        (next
         (when (= abs (org-today))
           (let* ((now (+endgame-today--now-minutes abs))
                  (item (seq-find (lambda (i)
                                    (and (not (alist-get 'done i)) (alist-get 'start i)
                                         (> (or (alist-get 'end i) (1+ (alist-get 'start i))) now)))
                                  items)))
             (and item (cons `(in . ,(- (alist-get 'start item) now)) item))))))
    (cons clocking next)))

(defun +endgame-today-data (&optional date)
  "Everything the dashboard and the phone show for DATE (nil for today).
`+endgame-today-items' plus week, inbox, clocked, clocking, next and
watch_out (inbox count, deadlines ahead, rollover offenders)."
  (let* ((data (+endgame-today-items date))
         (abs (+endgame-today--abs (alist-get 'date data)))
         (items (alist-get 'items data))
         (clocked (+endgame-today-clocked (alist-get 'date data)))
         (now (+endgame-today-now abs items clocked))
         (inbox (+endgame-today-inbox-count)))
    (append data
            `((week . ,(+endgame-today-week abs))
              (inbox . ,inbox)
              (clocked . ,clocked)
              (clocking . ,(car now))
              (next . ,(cdr now))
              (watch-out . ((inbox . ,inbox)
                            (deadlines . ,(alist-get 'ahead data))
                            (rollovers . ,(seq-filter
                                           (lambda (i)
                                             (and (not (alist-get 'done i))
                                                  (or (>= (or (alist-get 'rollover i) 0)
                                                          +endgame-today-rollover-limit)
                                                      (alist-get 'overdue i))))
                                           items))))))))

(defun +endgame-today-area-week (abs)
  "Clocked minutes per area tag over day ABS's week so far, or nil.
Needs the capture module's `+endgame-areas-report'."
  (when (fboundp '+endgame-areas-report)
    (let* ((dow (calendar-day-of-week (calendar-gregorian-from-absolute abs)))
           (monday (- abs (mod (+ dow 6) 7))))
      (mapcar (lambda (a) (cons (alist-get 'tag a) (alist-get 'clocked a)))
              (+endgame-areas-report (+endgame-today--date monday) (+endgame-today--date abs))))))

;;;; Dashboard

(defface +endgame-today-header '((t :inherit org-level-1 :height 1.0))
  "The dashboard's title line.")

(defface +endgame-today-section '((t :inherit org-level-2 :height 1.0))
  "A section heading of the dashboard.")

(defface +endgame-today-time '((t :inherit org-date :underline nil))
  "An item's time.")

(defface +endgame-today-done '((t :inherit org-agenda-done))
  "A done item.")

(defface +endgame-today-late '((t :inherit org-scheduled-previously))
  "Rollover and overdue marks.")

(defface +endgame-today-count '((t :inherit org-checkbox-statistics-todo))
  "Counters.")

(defvar-local +endgame-today--shown nil
  "Absolute day the dashboard shows.")

(defvar-local +endgame-today--dirty nil
  "Non-nil when something changed while the dashboard was out of sight.")

(defvar +endgame-today--refresh-timer nil
  "Periodic refresh of a visible dashboard.")

(defvar +endgame-today--pending nil
  "Idle timer of a refresh asked for by a hook.")

(defcustom +endgame-today-slow-every 300
  "Seconds the per-area numbers are kept before they're read again.
They're clocktables over every area's sources, the slow part of a
refresh, and only a clock-out changes them; gr reads them now."
  :type 'integer)

(defvar +endgame-today--slow-cache nil
  "(DAY TIME . VALUE): the per-area numbers of the last refresh.")

(defun +endgame-today--slow (abs fn)
  "FN's value for day ABS, from the cache while it's fresh."
  (if (and (eql (car +endgame-today--slow-cache) abs)
           (< (float-time (time-subtract nil (cadr +endgame-today--slow-cache)))
              +endgame-today-slow-every))
      (cddr +endgame-today--slow-cache)
    (let ((value (funcall fn)))
      (setq +endgame-today--slow-cache (cons abs (cons (current-time) value)))
      value)))

(defun +endgame-today--forget-slow (&rest _)
  "Read the per-area numbers again on the next refresh."
  (setq +endgame-today--slow-cache nil))

(add-hook 'org-clock-out-hook #'+endgame-today--forget-slow)

(defvar +endgame-today--timeline-files nil
  "Files the panel's timeline reads, instead of every agenda file.")

(defun +endgame-today--kind-icon (kind)
  "One character for KIND."
  (pcase kind ('habit "↻") ('session "◆") ('routine "≡") ('appt "●") (_ " ")))

(defun +endgame-today--put-action (start action &optional item)
  "Mark START to the end of the line with ACTION (a command) and ITEM."
  (add-text-properties start (line-end-position)
                       `(+endgame-today-action ,action +endgame-today-item ,item)))

(defun +endgame-today--align-right (columns)
  "Space that pushes the next COLUMNS columns against the window's right edge.
A display spec rather than counted spaces: icons and dashes from a
fallback font are wider than one column, which shifted counted text off
the window."
  (propertize " " 'display `(space :align-to (- right ,(* (1+ columns) (+endgame-today--zoom))))))

(defun +endgame-today--no-tab-line ()
  "No tab line in this buffer.
centaur-tabs draws its tabs in the tab line, set by default for every
buffer; the panel's buffers aren't in its tab groups, so it was an empty
line on top of each window."
  (setq-local tab-line-format nil))

(defun +endgame-today--zoom ()
  "How much the current buffer's text is zoomed, as a factor (1.0 = not)."
  (if (bound-and-true-p text-scale-mode)
      (expt text-scale-mode-step text-scale-mode-amount)
    1.0))

(defun +endgame-today--insert-item (item width)
  "Insert ITEM as one line of a WIDTH-column window."
  (let* ((start (point))
         (done (alist-get 'done item))
         (box (cond ((not (alist-get 'checkable item)) "   ")
                    (done "[x]")
                    (t "[ ]")))
         (time (if (alist-get 'start item)
                   (concat (+endgame-today--hhmm (alist-get 'start item))
                           (if (alist-get 'end item)
                               (concat "–" (+endgame-today--hhmm (alist-get 'end item)))
                             "      "))
                 (make-string 11 ?\s)))
         (late (cond ((alist-get 'rollover item) (format "Sched. %dx" (alist-get 'rollover item)))
                     ((alist-get 'overdue item) (format "%dd late" (alist-get 'overdue item)))))
         (right (string-join (delq nil (list (alist-get 'progress item)
                                             late
                                             (alist-get 'area item)))
                             "  "))
         (room (max 10 (- width 3 1 11 2 2 (length right) 2)))
         (title (truncate-string-to-width (alist-get 'title item) room nil nil "…")))
    (insert " "
            (propertize box 'face (if done '+endgame-today-done 'org-checkbox))
            " "
            (propertize time 'face (if done '+endgame-today-done '+endgame-today-time))
            " "
            (propertize (+endgame-today--kind-icon (alist-get 'kind item)) 'face 'shadow)
            " "
            (propertize title 'face (if done '+endgame-today-done 'default)))
    (when (not (string-empty-p right))
      (insert (+endgame-today--align-right (string-width right))
              (string-join
               (delq nil (list (and (alist-get 'progress item)
                                    (propertize (alist-get 'progress item) 'face '+endgame-today-count))
                               (and late (propertize late 'face '+endgame-today-late))
                               (and (alist-get 'area item)
                                    (propertize (alist-get 'area item) 'face 'org-tag))))
               "  ")))
    (+endgame-today--put-action start #'+endgame-today/toggle item)
    (insert "\n")))

(defun +endgame-today--insert-habits (week width)
  "Insert this WEEK of habits (from `+habits-heatmap-data') in WIDTH columns."
  (let* ((colours (+habits-heatmap--colours))
         (all (alist-get 'all week))
         (start (point))
         (name-width (min 22 (max 10 (- width 22)))))
    (insert (propertize "HABITS" 'face '+endgame-today-section)
            (propertize (format "   %d/%d today · streak %dd · record %dd\n"
                                (alist-get 'done all) (alist-get 'total all)
                                (alist-get 'streak all) (alist-get 'record all))
                        'face 'shadow))
    (+endgame-today--put-action start #'+endgame-today/heatmap)
    (insert (make-string (+ 3 name-width) ?\s)
            (propertize "M T W T F S S\n" 'face 'shadow))
    (cl-flet ((row (title grid action)
                (let ((s (point)))
                  (insert "   " (truncate-string-to-width title (1- name-width) nil ?\s "…") " ")
                  (seq-doseq (cell (aref grid 0))
                    (insert (if (eq (alist-get 'future cell) t)
                                (propertize "·" 'face 'shadow)
                              (propertize "■" 'face `(:foreground ,(aref colours (alist-get 'level cell)))
                                          'help-echo (alist-get 'date cell)))
                            " "))
                  (+endgame-today--put-action s action)
                  (insert "\n"))))
      (row "all" (alist-get 'grid all) #'+endgame-today/heatmap)
      (seq-doseq (h (alist-get 'habits week))
        (row (alist-get 'title h) (alist-get 'grid h) #'+endgame-today/heatmap)))))

(defun +endgame-today--insert-clocked (clocked width)
  "Insert CLOCKED (from `+endgame-today-clocked') in WIDTH columns."
  (let ((start (point)))
    (insert (propertize "CLOCKED" 'face '+endgame-today-section)
            "  " (propertize (+endgame-today--duration (alist-get 'total clocked))
                             'face '+endgame-today-count)
            (propertize "   RET: the day's clocktable" 'face 'shadow)
            "\n")
    (+endgame-today--put-action start #'+endgame-today/clock-report))
  (let ((rows (alist-get 'headings clocked)))
    (when (null rows)
      (insert (propertize "   nothing clocked yet\n" 'face 'shadow)))
    (dolist (row (seq-take rows +endgame-today-clocked-rows))
      (let ((s (point)))
        (insert "   " (propertize (format "%5s" (+endgame-today--duration (alist-get 'minutes row)))
                                  'face (if (alist-get 'running row) 'success '+endgame-today-time))
                "  " (truncate-string-to-width (alist-get 'title row) (max 10 (- width 30)) nil nil "…")
                "  " (propertize (truncate-string-to-width (alist-get 'note row) 18 nil nil "…")
                                 'face 'shadow))
        (+endgame-today--put-action s #'+endgame-today/visit row)
        (insert "\n")))))

(defun +endgame-today--insert-areas (areas week)
  "Insert today's planned vs clocked for AREAS, and the WEEK's clocked.
AREAS is from `+endgame-today-area-time', WEEK an alist of tag and
minutes from `+endgame-today-area-week'."
  (let ((rows (seq-filter (lambda (a) (or (> (or (alist-get 'planned a) 0) 0)
                                          (> (or (alist-get 'clocked a) 0) 0)
                                          (> (or (cdr (assoc (alist-get 'tag a) week)) 0) 0)
                                          (alist-get 'baselineDay a)
                                          (alist-get 'baselineWeek a)))
                          areas)))
    (insert (propertize "AREAS" 'face '+endgame-today-section)
            (propertize (if (fboundp '+endgame-areas-report)
                            "   today: planned  clocked / base    week: clocked / base\n"
                          "   planned today (clocked needs the capture module)\n")
                        'face 'shadow))
    (when (null rows)
      (insert (propertize "   no sessions planned\n" 'face 'shadow)))
    (dolist (a rows)
      (let* ((s (point))
             (planned (or (alist-get 'planned a) 0))
             (actual (alist-get 'clocked a))
             (wk (cdr (assoc (alist-get 'tag a) week)))
             (base (lambda (m) (propertize (if m (format " / %-5s" (+endgame-today--duration m)) "        ")
                                           'face 'shadow))))
        (insert "   " (truncate-string-to-width (or (alist-get 'name a) (alist-get 'tag a)) 18 nil ?\s "…")
                "  " (propertize (format "%5s" (+endgame-today--duration planned)) 'face '+endgame-today-time)
                "  " (propertize (format "%5s" (if actual (+endgame-today--duration actual) "–"))
                                 'face (if (and actual (> planned 0) (>= actual planned))
                                           'success '+endgame-today-count))
                (funcall base (alist-get 'baselineDay a))
                (if week
                    (concat "  " (propertize (format "%5s" (if wk (+endgame-today--duration wk) "–"))
                                             'face '+endgame-today-count)
                            (funcall base (alist-get 'baselineWeek a)))
                  ""))
        (+endgame-today--put-action s #'+endgame-today/visit-area a)
        (insert "\n")))))

(defun +endgame-today--insert-now (clocking next)
  "Insert the running CLOCKING and the NEXT timed item.
Both as `+endgame-today-now' returns them."
  (when clocking
    (let ((s (point)))
      (insert "   " (propertize (format "▶ %s" (+endgame-today--duration (alist-get 'minutes clocking)))
                               'face 'success)
              "  " (alist-get 'title clocking)
              (propertize (format "  since %s" (format-time-string "%H:%M" (alist-get 'since clocking)))
                          'face 'shadow))
      (+endgame-today--put-action s #'+endgame-today/visit
                                  `((title . ,(alist-get 'title clocking))
                                    (marker . ,(alist-get 'marker clocking))))
      (insert "\n")))
  (when next
    (let ((s (point))
          (in (alist-get 'in next)))
      (insert "   " (propertize "▸" 'face '+endgame-today-time) " "
              (propertize (if (> in 0)
                              (+endgame-today--hhmm (alist-get 'start next))
                            "now  ")
                          'face '+endgame-today-time)
              " " (alist-get 'title next)
              (propertize (cond ((> in 90) (format "  in %s" (+endgame-today--duration in)))
                                ((> in 0) (format "  in %d min" in))
                                ((alist-get 'end next)
                                 (format "  until %s" (+endgame-today--hhmm (alist-get 'end next))))
                                (t ""))
                          'face 'shadow))
      (+endgame-today--put-action s #'+endgame-today/toggle next)
      (insert "\n"))))

(defun +endgame-today--insert-watch-out (watch)
  "Insert WATCH (from `+endgame-today-data'): inbox, deadlines, rollovers."
  (let ((inbox (alist-get 'inbox watch))
        (deadlines (alist-get 'deadlines watch))
        (rollovers (alist-get 'rollovers watch)))
    (when (or (> inbox 0) deadlines rollovers)
      (insert "\n" (propertize "WATCH OUT" 'face '+endgame-today-section) "\n")
      (when (> inbox 0)
        (let ((s (point)))
          (insert "   " (propertize (format "%-11s" "inbox") 'face '+endgame-today-late)
                  (format " %d to process" inbox))
          (+endgame-today--put-action s #'+endgame-today/inbox)
          (insert "\n")))
      (dolist (item deadlines)
        (let ((s (point)))
          (insert "   " (propertize (format "%-11s" (or (alist-get 'agenda item) "")) 'face '+endgame-today-late)
                  " " (alist-get 'title item))
          (+endgame-today--put-action s #'+endgame-today/visit item)
          (insert "\n")))
      (dolist (item rollovers)
        (let ((s (point)))
          (insert "   " (propertize (format "%-11s" (if (alist-get 'rollover item)
                                                       (format "Sched. %dx" (alist-get 'rollover item))
                                                     (format "%dd late" (alist-get 'overdue item))))
                                    'face 'error)
                  " " (alist-get 'title item)
                  (propertize "  do it, date it or kill it" 'face 'shadow))
          (+endgame-today--put-action s #'+endgame-today/visit item)
          (insert "\n"))))))

(defun +endgame-today--render (abs)
  "Fill the dashboard (current buffer) with day ABS."
  (let* ((inhibit-read-only t)
         (win (get-buffer-window (current-buffer) t))
         ;; one column short of the window, or the last one wraps; `remap'
         ;; counts columns of the zoomed text (`+endgame-today-text-scale')
         (width (1- (if win (window-body-width win 'remap) 80)))
         (date (+endgame-today--date abs))
         (data (+endgame-today-data date))
         (items (alist-get 'items data))
         (counts (alist-get 'counts data))
         (week (alist-get 'week data))
         (title (format "%s · W%02d" (format-time-string "TODAY · %a %d %b" (+endgame-today--time abs))
                        (alist-get 'number week)))
         (count (format "%d/%d" (alist-get 'done counts) (alist-get 'total counts))))
    (setq +endgame-today--shown abs
          +endgame-today--dirty nil
          +endgame-today--timeline-files
          (delete-dups (append (mapcar (lambda (i) (+endgame-today--vault-file (alist-get 'file i))) items)
                               (seq-filter #'file-exists-p
                                           (list (+endgame-today--day-file abs)
                                                 (+endgame-today--upcoming-file)
                                                 (+endgame-today--life-file))))))
    (erase-buffer)
    (let ((s (point)))
      (insert (propertize title 'face '+endgame-today-header)
              (+endgame-today--align-right (length count))
              (propertize count 'face '+endgame-today-count) "\n")
      (+endgame-today--put-action s #'+endgame/today-agenda))
    (let ((s (point)))
      (insert "   " (if (alist-get 'priority week)
                         (propertize (truncate-string-to-width (alist-get 'priority week) (- width 3) nil nil "…")
                                     'face 'italic)
                       (propertize "no weekly priority yet: RET to write it" 'face 'shadow)))
      (+endgame-today--put-action s #'+endgame-today/week)
      (insert "\n"))
    (+endgame-today--insert-now (alist-get 'clocking data) (alist-get 'next data))
    (insert "\n")
    (if items
        (dolist (item items) (+endgame-today--insert-item item width))
      (insert (propertize "   nothing planned. planning = scheduling (C-c C-s .)\n" 'face 'shadow)))
    (let ((habits (+endgame-today--habit-week)))
      (when habits
        (insert "\n")
        (+endgame-today--insert-habits habits width)))
    (insert "\n")
    (+endgame-today--insert-clocked (alist-get 'clocked data) width)
    (insert "\n")
    (pcase-let ((`(,day . ,week)
                 (+endgame-today--slow abs (lambda ()
                                             (cons (ignore-errors (+endgame-today-area-time date items))
                                                   (ignore-errors (+endgame-today-area-week abs)))))))
      (+endgame-today--insert-areas day week))
    (+endgame-today--insert-watch-out (alist-get 'watch-out data))
    (insert "\n" (propertize "RET tick · TAB visit · t state · s schedule · S unschedule · d deadline · I/O clock · gr refresh"
                             'face 'shadow))))

(defun +endgame-today-refresh (&rest _)
  "Redraw the dashboard, keeping point on the same line.
Interactively, also read the per-area numbers again."
  (interactive)
  (when (called-interactively-p 'any) (+endgame-today--forget-slow))
  (when-let* ((buf (get-buffer +endgame-today-dashboard-buffer)))
    (with-current-buffer buf
      (let ((ref (alist-get 'ref (get-text-property (point) '+endgame-today-item)))
            (line (line-number-at-pos))
            (win (get-buffer-window buf t)))
        (+endgame-today--render (org-today))
        (goto-char (point-min))
        (or (and ref (text-property-search-forward
                      '+endgame-today-item ref
                      (lambda (r item) (equal r (alist-get 'ref item)))))
            (forward-line (1- line)))
        (beginning-of-line)
        (when win (set-window-point win (point)))))))

(defun +endgame-today--refresh-panel ()
  "Refresh the dashboard, and the timeline and note when the day changed."
  (let ((buf (get-buffer +endgame-today-dashboard-buffer)))
    (when buf
      (let ((day-changed (not (eql (buffer-local-value '+endgame-today--shown buf) (org-today)))))
        (+endgame-today-refresh)
        (+endgame-today--redraw-timeline)
        (when day-changed
          ;; a note left on yesterday follows the day; any other day stays,
          ;; with its header ("today", "2d ago") worked out again
          (dolist (win (window-list nil 'no-mini))
            (with-current-buffer (window-buffer win)
              (when +endgame-today-note-mode
                (if (eql +endgame-today-note--day (1- (org-today)))
                    (+endgame-today--note-show (org-today) win)
                  (setq +endgame-today-note--header
                        (+endgame-today--note-header +endgame-today-note--day)))))))))))

(defun +endgame-today--idle-refresh ()
  "Run a refresh a hook asked for."
  (setq +endgame-today--pending nil)
  (+endgame-today--refresh-panel))

(defun +endgame-today--changed-h (&rest _)
  "Something in the vault changed: refresh the dashboard soon.
When it's out of sight, refresh it once it's seen again."
  (when-let* ((buf (get-buffer +endgame-today-dashboard-buffer)))
    (if (get-buffer-window buf 'visible)
        (unless +endgame-today--pending
          (setq +endgame-today--pending
                (run-with-idle-timer 0.5 nil #'+endgame-today--idle-refresh)))
      (with-current-buffer buf (setq +endgame-today--dirty t)))))

(defun +endgame-today--saved-h ()
  "On `after-save-hook': an org file changed."
  (when (derived-mode-p 'org-mode) (+endgame-today--changed-h)))

(defun +endgame-today--tick ()
  "The periodic refresh: the clock moves, and the day ends.
A day ends at `org-extend-today-until', not midnight."
  (let ((buf (get-buffer +endgame-today-dashboard-buffer)))
    (cond ((not buf) (+endgame-today--stop-timer))
          ((get-buffer-window buf 'visible) (+endgame-today--refresh-panel))
          (t (with-current-buffer buf (setq +endgame-today--dirty t))))))

(defun +endgame-today--stop-timer ()
  "Stop the periodic refresh and forget the timeline's files."
  (when (timerp +endgame-today--refresh-timer) (cancel-timer +endgame-today--refresh-timer))
  (setq +endgame-today--refresh-timer nil
        +endgame-today--timeline-files nil))

(defun +endgame-today--shown-h (_window)
  "The dashboard came into view: catch up on what changed meanwhile."
  (when +endgame-today--dirty
    (+endgame-today--changed-h)))

(add-hook 'org-after-todo-state-change-hook #'+endgame-today--changed-h)
(add-hook 'org-checkbox-statistics-hook #'+endgame-today--changed-h)
(add-hook 'org-clock-in-hook #'+endgame-today--changed-h)
(add-hook 'org-clock-out-hook #'+endgame-today--changed-h)
(add-hook 'after-save-hook #'+endgame-today--saved-h)

;;;; Dashboard actions

(defun +endgame-today--at-point ()
  "The item or row on this line, or an error."
  (or (get-text-property (line-beginning-position) '+endgame-today-item)
      (get-text-property (point) '+endgame-today-item)
      (user-error "Nothing on this line")))

(defun +endgame-today--marker (item)
  "A live marker at ITEM's heading: its own, or found again by ID or file and line."
  (let ((m (alist-get 'marker item)))
    (or (and (markerp m) (marker-buffer m)
             (with-current-buffer (marker-buffer m)
               (org-with-wide-buffer
                (goto-char m)
                (and (org-at-heading-p)
                     (or (not (alist-get 'title item))
                         (string-prefix-p (alist-get 'title item)
                                          (car (+endgame-today--heading-parts))))
                     m))))
        (let ((id (alist-get 'id item)))
          (and id (org-id-find id 'marker)))
        (let ((file (and (alist-get 'file item) (+endgame-today--vault-file (alist-get 'file item)))))
          (when (and file (file-exists-p file))
            (with-current-buffer (+endgame-today--buffer file)
              (org-with-wide-buffer
               (goto-char (point-min))
               (forward-line (1- (alist-get 'line item)))
               (and (org-at-heading-p) (point-marker))))))
        (user-error "Can't find \"%s\" any more; gr to refresh" (alist-get 'title item)))))

(defvar +endgame-today--was (make-hash-table :test #'equal)
  "Item ref -> the open state it had when the dashboard ticked it.")

(defun +endgame-today--reopen-state (item)
  "The open state ITEM (the heading at point) had before it was done.
What it had when the dashboard ticked it, else its newest state note,
else APPT for an appointment, else its keyword sequence's first state."
  (let ((end (save-excursion (outline-next-heading) (point)))
        (open (lambda (s) (and s (member s org-not-done-keywords) s))))
    (or (funcall open (gethash (alist-get 'ref item) +endgame-today--was))
        (save-excursion
          (and (re-search-forward "^[ \t]*- State \"[^\"]+\"[ \t]+from \"\\([^\"]+\\)\"" end t)
               (funcall open (match-string 1))))
        (and (eq (alist-get 'kind item) 'appt) (funcall open "APPT"))
        (nth 2 (assoc (org-get-todo-state) org-todo-kwd-alist))
        (car org-not-done-keywords))))

(defun +endgame-today--save (buffer)
  "Save BUFFER after a change from the dashboard, if that's wanted."
  (when (and +endgame-today-save-after-change (buffer-modified-p buffer))
    (with-current-buffer buffer (save-buffer))))

(defmacro +endgame-today--at-item (&rest body)
  "Run BODY at the heading of the item on this line, then save and refresh."
  (declare (indent 0))
  `(let* ((item (+endgame-today--at-point))
          (m (+endgame-today--marker item)))
     (unwind-protect
         (with-current-buffer (marker-buffer m)
           (org-with-wide-buffer
            (goto-char m)
            ,@body)
           (+endgame-today--save (current-buffer)))
       (+endgame-today-refresh)
       (+endgame-today--redraw-timeline))))

(defun +endgame-today/toggle ()
  "Tick the item on this line: done, or back to the state it had.
On a line that isn't an item, run what the line leads to."
  (interactive)
  (let ((action (get-text-property (line-beginning-position) '+endgame-today-action)))
    (cond ((null action) (user-error "Nothing on this line"))
          ((not (eq action #'+endgame-today/toggle)) (call-interactively action))
          ((not (alist-get 'checkable (+endgame-today--at-point)))
           (+endgame-today/visit))
          (t (+endgame-today--at-item
               (let ((state (org-get-todo-state)))
                 (if (member state org-done-keywords)
                     (org-todo (+endgame-today--reopen-state item))
                   (puthash (alist-get 'ref item) state +endgame-today--was)
                   (org-todo 'done))))))))

(defun +endgame-today/todo ()
  "Set the state of the item on this line, picking it."
  (interactive)
  (+endgame-today--at-item (call-interactively #'org-todo)))

(defun +endgame-today/schedule ()
  "Not today: give the item on this line a new date."
  (interactive)
  (+endgame-today--at-item (call-interactively #'org-schedule)))

(defun +endgame-today/unschedule ()
  "Not anytime soon: remove the item's SCHEDULED date, back to the backlog."
  (interactive)
  (+endgame-today--at-item (org-schedule '(4))))

(defun +endgame-today/deadline ()
  "Set the deadline of the item on this line."
  (interactive)
  (+endgame-today--at-item (call-interactively #'org-deadline)))

(defun +endgame-today/clock-in ()
  "Clock in to the item on this line."
  (interactive)
  (+endgame-today--at-item (org-clock-in)))

(defun +endgame-today/visit ()
  "Show the heading on this line: in the daily note window when it's today's."
  (interactive)
  (let* ((m (+endgame-today--marker (+endgame-today--at-point)))
         (note (get-buffer (+endgame-today--note-name (or +endgame-today--shown (org-today)))))
         (win (and note (get-buffer-window note)))
         (in-note (and win (eq (buffer-base-buffer note) (marker-buffer m))
                       (with-current-buffer note (<= (point-min) m (point-max))))))
    (if in-note
        (progn (select-window win) (goto-char m))
      (pop-to-buffer (marker-buffer m))
      (when (fboundp 'my/org-full-setup-maybe) (my/org-full-setup-maybe))
      (widen)
      (goto-char m))
    (org-fold-show-context 'agenda)
    (org-fold-show-entry)))

(defun +endgame-today/visit-area ()
  "Open the area registry at the area on this line."
  (interactive)
  (let* ((area (+endgame-today--at-point))
         (file (+endgame-today--areas-file)))
    (find-file-other-window file)
    (widen)
    (goto-char (point-min))
    (when (re-search-forward (format "^[ \t]*:AREA_TAG:[ \t]+%s[ \t]*$" (regexp-quote (alist-get 'tag area))) nil t)
      (org-back-to-heading t)
      (org-fold-show-entry))))

(defun +endgame-today/week ()
  "Open the weekly note at its top, where the week's priority is written."
  (interactive)
  (let ((file (+endgame-today--day-file (or +endgame-today--shown (org-today)))))
    (unless (file-exists-p file) (user-error "No weekly note for this week yet"))
    (find-file-other-window file)
    (widen)
    (goto-char (point-min))
    (when (re-search-forward "^#\\+END:?[ \t]*$" (save-excursion (re-search-forward "^\\* " nil t)) t)
      (forward-line 1))))

(defun +endgame-today/inbox ()
  "Open the inbox note to process it."
  (interactive)
  (find-file-other-window (+endgame-today--inbox-file))
  (goto-char (point-min))
  (re-search-forward "^\\* " nil t)
  (beginning-of-line))

(defun +endgame-today/heatmap ()
  "The full habit heatmaps."
  (interactive)
  (if (fboundp '+habits/heatmap)
      (let ((display-buffer-overriding-action '(display-buffer-pop-up-window)))
        (+habits/heatmap))
    (user-error "No heatmap code loaded")))

(defun +endgame-today/clock-report ()
  "Go to the day's clocktable in the daily note and update it."
  (interactive)
  (let ((day (+endgame-today--day-marker (or +endgame-today--shown (org-today)))))
    (unless day (user-error "No daily note for this day yet"))
    (pop-to-buffer (marker-buffer day))
    (goto-char day)
    (when (re-search-forward "^#\\+BEGIN: clocktable" (save-excursion (org-end-of-subtree t t)) t)
      (org-update-dblock))))

(defvar-keymap +endgame-today-mode-map
  :parent special-mode-map
  "RET" #'+endgame-today/toggle
  "x" #'+endgame-today/toggle
  "TAB" #'+endgame-today/visit
  "o" #'+endgame-today/visit
  "t" #'+endgame-today/todo
  "s" #'+endgame-today/schedule
  "S" #'+endgame-today/unschedule
  "d" #'+endgame-today/deadline
  "I" #'+endgame-today/clock-in
  "O" #'org-clock-out
  "g" #'+endgame-today-refresh
  "n" #'next-line
  "p" #'previous-line)

(define-derived-mode +endgame-today-mode special-mode "Today"
  "The today dashboard: the today list, habits, clocked time, areas.
\\{+endgame-today-mode-map}"
  (setq-local revert-buffer-function (lambda (&rest _) (+endgame-today-refresh))
              truncate-lines t
              cursor-type 'bar)
  (setq-local display-line-numbers nil)
  (text-scale-set +endgame-today-text-scale)
  (+endgame-today--no-tab-line)
  (hl-line-mode 1)
  (add-hook 'window-buffer-change-functions #'+endgame-today--shown-h nil t)
  (add-hook 'kill-buffer-hook #'+endgame-today--stop-timer nil t)
  (unless (timerp +endgame-today--refresh-timer)
    (setq +endgame-today--refresh-timer
          (run-at-time +endgame-today-refresh-interval +endgame-today-refresh-interval
                       #'+endgame-today--tick))))

(defun +endgame-today--no-line-numbers-a (&rest _)
  "Before `display-line-numbers--turn-on': not in the dashboard or timeline.
The global mode turns them on after the mode hook, and they'd eat the
columns the lines are laid out in."
  (derived-mode-p '+endgame-today-mode 'org-timeblock-mode 'org-timeblock-list-mode))

(advice-add 'display-line-numbers--turn-on :before-until #'+endgame-today--no-line-numbers-a)

(defun +endgame-today-dashboard ()
  "The dashboard buffer, made if needed (not drawn)."
  (let ((buf (get-buffer-create +endgame-today-dashboard-buffer)))
    (with-current-buffer buf
      (unless (derived-mode-p '+endgame-today-mode) (+endgame-today-mode)))
    buf))

;;;; The panel: timeline, dashboard, daily note

(defvar org-timeblock-span)
(defvar org-timeblock-column)
(defvar org-timeblock-buffer)
(defvar org-timeblock-list-buffer)
(defvar org-timeblock-daterange)
(defvar org-timeblock-mode-map)
(declare-function org-timeblock-mode "org-timeblock")
(declare-function org-timeblock-redraw-buffers "org-timeblock")
(declare-function org-timeblock-redraw-timeblocks "org-timeblock")
(declare-function +workspace-exists-p "workspaces")
(declare-function +workspace-switch "workspaces")
(declare-function +habits-heatmap--colours "config")

;;;;; The daily note: one day, H / L to walk the days

(defvar-local +endgame-today-note--day nil
  "Absolute day the note buffer shows.")

(defvar-local +endgame-today-note--header nil
  "The note buffer's header line, worked out when the buffer is made.")

(defvar-keymap +endgame-today-note-mode-map
  :doc "Keys of the panel's daily note. Evil normal state gets them in Keys below."
  "C-c C-j" #'+endgame-today-note/next
  "C-c C-k" #'+endgame-today-note/previous)

(define-minor-mode +endgame-today-note-mode
  "One day's heading of a weekly journal note, in the today panel.
\\<+endgame-today-note-mode-map>The header line shows the day, where it
sits in its week, and the days before and after;
\\[+endgame-today-note/next] and \\[+endgame-today-note/previous] (L and H
in normal state, like day later/earlier in the timeline) move to them,
T goes back to today."
  :lighter nil
  (if +endgame-today-note-mode
      (progn (setq-local header-line-format '(:eval +endgame-today-note--header))
             (+endgame-today--no-tab-line))
    (kill-local-variable 'header-line-format)
    (kill-local-variable 'tab-line-format))
  ;; evil only sees a minor mode's state keys once its keymaps are
  ;; recomputed; turned on outside a command, that doesn't happen by itself
  (when (fboundp 'evil-normalize-keymaps) (evil-normalize-keymaps)))

(defun +endgame-today--note-name (abs)
  "Name of the indirect buffer narrowed to day ABS."
  (format "today: %s" (+endgame-today--date abs)))

(defun +endgame-today--note-day-p (abs)
  "Non-nil when day ABS has a heading in its weekly note."
  (when-let* ((m (+endgame-today--day-marker abs)))
    (set-marker m nil)
    t))

(defun +endgame-today--note-neighbor (abs dir)
  "The nearest day before (DIR -1) or after (DIR 1) ABS that has a note, or nil.
Looks `+endgame-today-note-search-days' days away at most."
  (cl-loop for i from 1 to +endgame-today-note-search-days
           for day = (+ abs (* dir i))
           when (+endgame-today--note-day-p day) return day))

(defun +endgame-today--note-week-days (abs)
  "The days that have a heading in day ABS's weekly note, in file order."
  (let ((file (+endgame-today--day-file abs)))
    (when (file-exists-p file)
      (with-current-buffer (+endgame-today--buffer file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (let (days)
           (while (re-search-forward "^\\* .*?\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" nil t)
             (push (+endgame-today--abs (match-string 1)) days))
           (nreverse days)))))))

(defun +endgame-today--note-header (abs)
  "Header line of the note showing day ABS: previous day, the day, next day."
  (let* ((prev (+endgame-today--note-neighbor abs -1))
         (next (+endgame-today--note-neighbor abs 1))
         (days (+endgame-today--note-week-days abs))
         (pos (cl-position abs days))
         (dow (calendar-day-of-week (calendar-gregorian-from-absolute abs)))
         (week (format-time-string "W%V" (+endgame-today--time abs)))
         (short (lambda (d) (format-time-string "%a %d %b" (+endgame-today--time d))))
         (here (concat (propertize (format-time-string "%A %d %b" (+endgame-today--time abs))
                                   'face '+endgame-today-header)
                       (propertize
                        (concat
                         (cond ((= abs (org-today)) " · today")
                               ((< abs (org-today)) (format " · %dd ago" (- (org-today) abs)))
                               (t (format " · in %dd" (- abs (org-today)))))
                         (format " · %s day %d/7" week (1+ (mod (+ dow 6) 7)))
                         (if pos (format " · note %d/%d" (1+ pos) (length days)) ""))
                        'face 'shadow))))
    (concat " "
            (propertize (if prev (format "‹ H %s" (funcall short prev)) "‹ none")
                        'face (if prev '+endgame-today-time 'shadow))
            "   " here "   "
            (propertize (if next (format "%s L ›" (funcall short next)) "none ›")
                        'face (if next '+endgame-today-time 'shadow)))))

(defun +endgame-today--note-setup (abs)
  "Make the current buffer the panel's note for day ABS."
  (setq +endgame-today-note--day abs
        +endgame-today-note--header (+endgame-today--note-header abs))
  (+endgame-today-note-mode 1)
  (when (fboundp 'text-scale-set) (text-scale-set +endgame-today-text-scale)))

(defun +endgame-today--note-buffer (abs)
  "An indirect buffer of the weekly journal file narrowed to day ABS.
Indirect, so the file's own buffer stays whole for other windows; it
edits and saves the real file. Without the day's heading, a placeholder
that still walks the days, never the whole week."
  (let ((name (+endgame-today--note-name abs)))
    (or (let ((buf (get-buffer name)))
          ;; a placeholder made before the day existed is stale once it does
          (if (and buf (not (buffer-base-buffer buf)) (+endgame-today--note-day-p abs))
              (progn (kill-buffer buf) nil)
            buf))
        (let ((day (+endgame-today--day-marker abs)))
          (if (not day)
              (with-current-buffer (get-buffer-create name)
                (let ((inhibit-read-only t))
                  (erase-buffer)
                  (insert (propertize (format "No daily note for %s.\n" (+endgame-today--date abs))
                                      'face 'shadow)))
                (special-mode)
                (+endgame-today--note-setup abs)
                (current-buffer))
            (let ((base (marker-buffer day)))
              (with-current-buffer base
                (when (fboundp 'my/org-full-setup-maybe) (my/org-full-setup-maybe)))
              (with-current-buffer (make-indirect-buffer base name t)
                (widen)
                (goto-char day)
                (org-narrow-to-subtree)
                (org-fold-show-subtree)
                (org-fold-hide-drawer-all)
                (goto-char (point-min))
                (set-marker day nil)
                (+endgame-today--note-setup abs)
                (current-buffer))))))))

(defun +endgame-today--note-show (abs window)
  "Show day ABS's note in WINDOW, dropping the note it showed before.
The dropped one is an indirect buffer or a placeholder: killing it loses
nothing, the edits are in the file's own buffer."
  (let ((old (window-buffer window))
        (new (+endgame-today--note-buffer abs)))
    (unless (eq old new)
      (set-window-buffer window new)
      (set-window-start window (with-current-buffer new (point-min)))
      (when (and (buffer-local-value '+endgame-today-note-mode old)
                 (not (get-buffer-window old t)))
        (kill-buffer old)))
    new))

(defun +endgame-today--note-step (dir n)
  "Move the selected note window N daily notes in direction DIR (1 or -1)."
  (let ((abs (or +endgame-today-note--day (user-error "Not a today-panel note"))))
    (dotimes (_ n)
      (setq abs (or (+endgame-today--note-neighbor abs dir)
                    (user-error "No %s daily note in %d days"
                                (if (> dir 0) "later" "earlier")
                                +endgame-today-note-search-days))))
    (+endgame-today--note-show abs (selected-window))))

(defun +endgame-today-note/next (&optional n)
  "Show the next day that has a daily note (N days with a prefix)."
  (interactive "p")
  (+endgame-today--note-step 1 (or n 1)))

(defun +endgame-today-note/previous (&optional n)
  "Show the previous day that has a daily note (N days with a prefix)."
  (interactive "p")
  (+endgame-today--note-step -1 (or n 1)))

(defun +endgame-today-note/today ()
  "Back to today's note."
  (interactive)
  (+endgame-today--note-show (org-today) (selected-window)))

(defun +endgame-today--note-window ()
  "The window of this frame showing a panel note, or nil."
  (seq-find (lambda (w) (buffer-local-value '+endgame-today-note-mode (window-buffer w)))
            (window-list)))

;;;;; The timeline: org-timeblock, in the theme's colours and zoomable

(defun +endgame-today--timeblock-files-a (fn)
  "Around `org-timeblock-files': the panel's own short list for its day.
org-timeblock opens every file it reads with its full setup; the agenda
files would be ~150 of them. Another day (H / L) needs them all."
  (if (and +endgame-today--timeline-files
           (bound-and-true-p org-timeblock-daterange)
           (eql (+endgame-today--decoded-abs (car org-timeblock-daterange))
                (when-let* ((buf (get-buffer +endgame-today-dashboard-buffer)))
                  (buffer-local-value '+endgame-today--shown buf))))
      +endgame-today--timeline-files
    (funcall fn)))

(defun +endgame-today--decoded-abs (time)
  "Absolute day of the decoded TIME."
  (calendar-absolute-from-gregorian
   (list (decoded-time-month time) (decoded-time-day time) (decoded-time-year time))))

(defun +endgame-today--rgb (color)
  "COLOR as (R G B) in 0..1, or nil. Hex is read directly, it works in batch too."
  (cond ((not (stringp color)) nil)
        ((string-match "\\`#\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\([[:xdigit:]]\\{2\\}\\)\\'" color)
         (mapcar (lambda (i) (/ (string-to-number (match-string i color) 16) 255.0)) '(1 2 3)))
        ((color-defined-p color) (color-name-to-rgb color))))

(defun +endgame-today--blend (color base alpha)
  "COLOR laid over BASE at ALPHA (0..1), as #rrggbb; nil if either isn't a colour."
  (let ((a (+endgame-today--rgb color)) (b (+endgame-today--rgb base)))
    (when (and a b)
      (apply #'format "#%02x%02x%02x"
             (cl-mapcar (lambda (x y) (round (* 255 (+ (* alpha x) (* (- 1 alpha) y))))) a b)))))

(defun +endgame-today--fg (face &optional fallback)
  "FACE's foreground as a colour string, or FALLBACK."
  (let ((c (and (facep face) (face-attribute face :foreground nil 'default))))
    (if (+endgame-today--rgb c) c fallback)))

(defun +endgame-today--timeline-palette ()
  "The theme's colours for the timeline, as an alist; nil without a theme bg."
  (let ((bg (face-attribute 'default :background nil t))
        (fg (face-attribute 'default :foreground nil t)))
    (when (and (+endgame-today--rgb bg) (+endgame-today--rgb fg))
      (require 'ansi-color nil t)
      `((bg . ,bg) (fg . ,fg)
        (dim . ,(+endgame-today--fg 'line-number (+endgame-today--blend fg bg 0.3)))
        ,@(mapcar (lambda (c) (cons c (+endgame-today--fg (intern (format "ansi-color-%s" c))
                                                            (+endgame-today--fg 'error))))
                  '(red green yellow blue magenta cyan))))))

(defun +endgame-today-timeline-faces ()
  "Give org-timeblock's faces the current theme's colours.
Blocks are the theme's red, green, … as text over a dim tint of it."
  (when-let* ((pal (+endgame-today--timeline-palette)))
    (let ((bg (alist-get 'bg pal)))
      (dolist (c '(red green yellow blue magenta cyan))
        (let ((col (alist-get c pal)))
          (face-spec-set (intern (format "org-timeblock-%s" c))
                         `((t :background ,(+endgame-today--blend col bg 0.28) :foreground ,col
                              :extend t))
                         'face-defface-spec)))
      (face-spec-set 'org-timeblock-select
                     `((t :background ,(+endgame-today--blend (alist-get 'blue pal) bg 0.4)))
                     'face-defface-spec)
      (face-spec-set 'org-timeblock-mark
                     `((t :background ,(+endgame-today--blend (alist-get 'magenta pal) bg 0.5)))
                     'face-defface-spec)
      (face-spec-set 'org-timeblock-hours-line
                     `((t :background ,(alist-get 'dim pal))) 'face-defface-spec)
      (face-spec-set 'org-timeblock-current-time-indicator
                     `((t :background ,(alist-get 'red pal))) 'face-defface-spec))))

(defvar +endgame-today--svg-style nil
  "While the timeline draws: (COLOURS SIZE FAMILY) for `+endgame-today--svg-a'.
COLOURS maps org-timeblock's hard-coded ((ATTR . COLOUR) . THEME-COLOUR).")

(defun +endgame-today--svg-fix (args n)
  "ARGS of an svg call whose first N are positional, restyled by the theme."
  (pcase-let ((`(,colours ,size ,family) +endgame-today--svg-style))
    (let ((head (seq-take args n))
          (plist (copy-sequence (nthcdr n args))))
      (dolist (key '(:fill :stroke))
        (when-let* ((v (plist-get plist key))
                    (new (and (stringp v)
                              (alist-get (cons key (downcase v)) colours nil nil #'equal))))
          (setq plist (plist-put plist key new))))
      (when (and (= n 2) size)          ; svg-text: the zoomed size, the buffer's font
        (setq plist (plist-put plist :font-size size))
        (when (and family (not (plist-get plist :font-family)))
          (setq plist (plist-put plist :font-family family))))
      (append head plist))))

(defun +endgame-today--svg-rect-a (args)
  "Filter-args of `svg-rectangle' while the timeline draws."
  (if +endgame-today--svg-style (+endgame-today--svg-fix args 5) args))

(defun +endgame-today--svg-text-a (args)
  "Filter-args of `svg-text' while the timeline draws."
  (if +endgame-today--svg-style (+endgame-today--svg-fix args 2) args))

(defvar org-timeblock-svg)

(defun +endgame-today--svg-image-a (args)
  "Filter-args of `svg-image': the timeline's image at its own size.
With `image-scaling-factor' at `auto', Emacs enlarges images by the
font's width over 10 pixels; the timeline is drawn exactly the window's
size, so a wide font pushed its right edge (block borders, the times)
out of the window."
  (if (and (bound-and-true-p org-timeblock-svg)
           (eq (car args) org-timeblock-svg)
           (not (plist-member (cdr args) :scale)))
      (append args '(:scale 1))
    args))

(defun +endgame-today--timeline-draw-a (fn &rest args)
  "Around `org-timeblock-redraw-timeblocks': theme colours and the buffer's zoom.
The timeline is one SVG exactly the window's size, so text-scale can't
reach it: its font size and the line heights it lays text out with are
scaled here instead, by the timeline buffer's own `text-scale-mode' zoom."
  (if (not (display-graphic-p))
      (apply fn args)
    (let* ((zoom (with-current-buffer (get-buffer-create org-timeblock-buffer) (+endgame-today--zoom)))
           (w (default-font-width))
           (h (default-font-height))
           (pal (+endgame-today--timeline-palette))
           (red (alist-get 'red pal))
           (bg (alist-get 'bg pal))
           (+endgame-today--svg-style
            (list (and pal
                       `(((:stroke . "#5b0103") . ,red)                         ; events
                         ((:fill . "#5b0103") . ,(+endgame-today--blend red bg 0.45)) ; deadlines
                         ((:stroke . "#cdcdcd") . ,(alist-get 'dim pal))        ; block borders
                         ((:fill . "#ffffff") . ,(alist-get 'fg pal))))         ; deadline text
                  (max 6 (round (* zoom (aref (font-info (face-font 'default)) 2))))
                  (face-attribute 'default :family nil t))))
      (cl-letf (((symbol-function 'default-font-width) (lambda () (max 1 (round (* zoom w)))))
                ((symbol-function 'default-font-height) (lambda () (max 1 (round (* zoom h))))))
        (apply fn args)))))

(defun +endgame-today--timeline-rezoom-h ()
  "On `text-scale-mode-hook' in the timeline: draw it at the new size."
  (when (derived-mode-p 'org-timeblock-mode)
    (ignore-errors (org-timeblock-redraw-timeblocks))))

(defun +endgame-today--timeline-mode-h ()
  "In org-timeblock's buffers: no line numbers, the panel's zoom."
  (when (bound-and-true-p display-line-numbers-mode) (display-line-numbers-mode -1))
  (setq-local display-line-numbers nil)
  (+endgame-today--no-tab-line)
  (when (derived-mode-p 'org-timeblock-mode)
    (add-hook 'text-scale-mode-hook #'+endgame-today--timeline-rezoom-h nil t))
  (text-scale-set +endgame-today-text-scale))

(with-eval-after-load 'org-timeblock
  (advice-add 'org-timeblock-files :around #'+endgame-today--timeblock-files-a)
  (advice-add 'org-timeblock-redraw-timeblocks :around #'+endgame-today--timeline-draw-a)
  (advice-add 'svg-rectangle :filter-args #'+endgame-today--svg-rect-a)
  (advice-add 'svg-text :filter-args #'+endgame-today--svg-text-a)
  (advice-add 'svg-image :filter-args #'+endgame-today--svg-image-a)
  (add-hook 'org-timeblock-mode-hook #'+endgame-today--timeline-mode-h)
  (add-hook 'org-timeblock-list-mode-hook #'+endgame-today--timeline-mode-h)
  (+endgame-today-timeline-faces)
  (add-hook (if (boundp 'doom-load-theme-hook) 'doom-load-theme-hook 'enable-theme-functions)
            (lambda (&rest _) (+endgame-today-timeline-faces))))

(defun +endgame-today--timeline-p ()
  "Non-nil when org-timeblock can draw in this frame."
  (and (display-graphic-p) (image-type-available-p 'svg)
       (require 'org-timeblock nil t)))

(defun +endgame-today--timeline (abs window)
  "Show day ABS's timeline in WINDOW: org-timeblock, or a day agenda without it."
  (cond
   ((+endgame-today--timeline-p)
    (let ((day (decode-time (+endgame-today--time abs))))
      ;; for good, not let-bound: its commands read the span later, and with
      ;; the default 3 over a one-day range, H moved the selection to a
      ;; column 2 that isn't drawn, after which j / k found nothing
      (setq org-timeblock-span 1
            org-timeblock-column 1)
      (set-window-buffer window (get-buffer-create org-timeblock-buffer))
      (with-selected-window window
        (unless (derived-mode-p 'org-timeblock-mode) (org-timeblock-mode))
        (setq org-timeblock-daterange (cons day day))
        (org-timeblock-redraw-buffers))))
   ((require 'org-timeblock nil t)      ; a terminal: its text list
    (let ((day (decode-time (+endgame-today--time abs))))
      (setq org-timeblock-daterange (cons day day))
      (org-timeblock-redraw-buffers)
      (set-window-buffer window org-timeblock-list-buffer)))
   (t
    (with-selected-window window
      (let ((org-agenda-window-setup 'current-window)
            (org-agenda-sticky nil))
        (org-agenda-list nil abs 1))))))

(defun +endgame-today--redraw-timeline ()
  "Redraw a visible org-timeblock, which is cheap when nothing changed."
  (when (and (featurep 'org-timeblock) (get-buffer-window org-timeblock-buffer 'visible))
    (with-selected-window (get-buffer-window org-timeblock-buffer 'visible)
      (ignore-errors (org-timeblock-redraw-buffers)))))

;;;;; The panel

(defun +endgame-today--workspace ()
  "Switch to the panel's workspace (Doom) or tab, making it if needed.
Returns non-nil when it was there already."
  (let ((name +endgame-today-workspace))
    (cond ((and (fboundp '+workspace-switch) (bound-and-true-p persp-mode))
           (prog1 (+workspace-exists-p name)
             (+workspace-switch name t)))
          ((fboundp 'tab-bar-select-tab-by-name)
           (let ((there (seq-find (lambda (tab) (equal (alist-get 'name tab) name))
                                  (funcall tab-bar-tabs-function))))
             (if there
                 (tab-bar-select-tab-by-name name)
               (tab-bar-new-tab)
               (tab-bar-rename-tab name))
             there)))))

(defun +endgame/today-panel ()
  "The today panel: timeline left, dashboard right, the daily note under it.
Opens in its own workspace; run it again there to rebuild the layout and
bring the note back to today."
  (interactive)
  (when (fboundp '+endgame--ensure-day)  ; today's note, made the normal way (prompts)
    (+endgame--ensure-day (+endgame--today) t))
  (let ((abs (org-today))
        (there (+endgame-today--workspace))
        (dash (+endgame-today-dashboard)))
    (if (and there (get-buffer-window dash))
        (progn (select-window (get-buffer-window dash))
               (when-let* ((note (+endgame-today--note-window)))
                 (+endgame-today--note-show abs note))
               (+endgame-today--refresh-panel))
      (delete-other-windows)
      (let* ((left (selected-window))
             (right (split-window left (max 30 (round (* +endgame-today-timeline-width
                                                         (window-total-width left))))
                                  'right))
             (bottom (split-window right (- (round (* +endgame-today-note-height
                                                      (window-total-height right))))
                                   'below)))
        (set-window-buffer right dash)
        (+endgame-today--note-show abs bottom)
        (select-window right)
        (+endgame-today-refresh)
        (+endgame-today--timeline abs left)
        (goto-char (point-min))
        (forward-line 1)))))

;;;; Keys

(defun +endgame-today/zoom-in ()
  "Bigger text in this window (the timeline redraws at the new size)."
  (interactive)
  (text-scale-increase 1))

(defun +endgame-today/zoom-out ()
  "Smaller text in this window, so more fits."
  (interactive)
  (text-scale-decrease 1))

(defun +endgame-today/zoom-reset ()
  "Back to the panel's zoom, `+endgame-today-text-scale'."
  (interactive)
  (text-scale-set +endgame-today-text-scale))

(when (fboundp 'map!)
  (map! :leader
        :desc "Today panel" "o t" #'+endgame/today-panel
        :desc "Today list"  "o a d" #'+endgame/today-agenda
        :desc "Today list"  "n a d" #'+endgame/today-agenda)
  (map! :map +endgame-today-mode-map
        :n "RET" #'+endgame-today/toggle
        :n "x"   #'+endgame-today/toggle
        :n "TAB" #'+endgame-today/visit
        :n "o"   #'+endgame-today/visit
        :n "t"   #'+endgame-today/todo
        :n "s"   #'+endgame-today/schedule
        :n "S"   #'+endgame-today/unschedule
        :n "d"   #'+endgame-today/deadline
        :n "I"   #'+endgame-today/clock-in
        :n "O"   #'org-clock-out
        :n "gr"  #'+endgame-today-refresh
        :n "q"   #'quit-window)
  (map! :map +endgame-today-note-mode-map
        ;; C-j / C-k are Doom's heading jumps in org buffers; H / L match
        ;; day earlier / later in the timeline
        :n "L" #'+endgame-today-note/next
        :n "H" #'+endgame-today-note/previous
        :n "T" #'+endgame-today-note/today)
  ;; org-timeblock's own keys are single letters that evil's normal state
  ;; shadows (j, k, i, o, d, s, v…), so nothing worked there: the same
  ;; commands on vim-shaped keys
  (after! org-timeblock
    (map! :map org-timeblock-mode-map
          :n "j"   #'org-timeblock-forward-block
          :n "k"   #'org-timeblock-backward-block
          :n "h"   #'org-timeblock-backward-column
          :n "l"   #'org-timeblock-forward-column
          :n "H"   #'org-timeblock-day-earlier
          :n "L"   #'org-timeblock-day-later
          :n "gd"  #'org-timeblock-jump-to-day
          :n "RET" #'org-timeblock-goto
          :n "TAB" #'org-timeblock-goto-other-window
          :n "t"   #'org-timeblock-todo
          :n "s"   #'org-timeblock-schedule
          :n "d"   #'org-timeblock-set-duration
          :n "i"   #'org-timeblock-clock-in
          :n "I"   #'org-timeblock-clock-in
          :n "o"   #'org-clock-out
          :n "O"   #'org-clock-out
          :n "a"   #'org-timeblock-new-task
          :n "+"   #'org-timeblock-new-task
          :n "m"   #'org-timeblock-mark-block
          :n "u"   #'org-timeblock-unmark-block
          :n "U"   #'org-timeblock-unmark-all-blocks
          :n "%"   #'org-timeblock-mark-by-regexp
          :n "w"   #'org-timeblock-write
          :n "v"   #'org-timeblock-switch-scaling
          :n "V"   #'org-timeblock-change-span
          :n "T"   #'org-timeblock-toggle-timeblock-list
          :n "gr"  #'org-timeblock-redraw-buffers
          :n "-"   #'+endgame-today/zoom-out
          :n "="   #'+endgame-today/zoom-in
          :n "0"   #'+endgame-today/zoom-reset)))

(provide '+endgame-today)
;;; +endgame-today.el ends here

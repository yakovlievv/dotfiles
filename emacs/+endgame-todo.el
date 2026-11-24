;;; +endgame-todo.el --- changing a task: its state, its dates, its priority, by org itself -*- lexical-binding: t; -*-

;; What the phone, the calendar and Claude do to a task, done by org in the
;; vault-emacs daemon, so there is one implementation of what a state change
;; means: CLOSED, the LOGBOOK line, a repeater moving on, :RESET_CHECK_BOXES:,
;; blocked-by-open-subtasks, the parent's [n/m]. Nothing here re-implements any
;; of it: it finds the heading, calls org, saves, and says what happened.
;;
;; Every function takes the heading as FILE, LINE (1-based) and ID: the heading
;; with :ID: ID in FILE, else the heading on LINE. Like the other server entry
;; points (+endgame-capture-json, +endgame-day-ensure) they ask nothing, save the
;; buffers they change and return a JSON string with {"files": [...]}; a refusal
;; is an error starting "[invalid]", which the server turns into a 400.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'org)

(require '+endgame-capture)

(defun +endgame--locate (file line id)
  "Marker at the heading with :ID: ID in FILE, else the heading on LINE."
  (let* ((buf (+endgame--buffer file))
         (m (or (and id (+endgame--find-id buf id))
                (and line
                     (with-current-buffer buf
                       (org-with-wide-buffer
                        (goto-char (point-min))
                        (forward-line (1- line))
                        (and (org-at-heading-p) (point-marker))))))))
    (or m (+endgame--invalid "no heading %s in %s" (or id (format "on line %s" line)) (file-name-nondirectory file)))))

(defun +endgame--result (m &rest extra)
  "The answer for the heading at marker M: its file, line and id, plus EXTRA pairs."
  (with-current-buffer (marker-buffer m)
    (org-with-wide-buffer
     (goto-char m)
     (append `((file . ,(buffer-file-name (buffer-base-buffer)))
               (line . ,(line-number-at-pos nil t))
               (id . ,(org-entry-get nil "ID"))
               (state . ,(and (org-get-todo-state) (substring-no-properties (org-get-todo-state)))))
             extra))))

(defun +endgame--answer (result)
  "RESULT (an alist) as JSON with the files saved meanwhile."
  (+endgame--json
   (append result `((files . ,(vconcat (mapcar #'+endgame--relative (reverse +endgame--saved))))))))

;;; State

(defun +endgame--state-asks-for-note-p (state)
  "Non-nil when going to STATE asks for a note: the `@' of its keyword spec."
  (eq 'note (nth 1 (assoc state org-todo-log-states))))

(defun +endgame--todo-state-keywords ()
  "The keywords org knows, in a heading's buffer."
  org-todo-keywords-1)

(defun +endgame--change-state (m state note force)
  "Run org's own state change on the heading at M, answering the note question with NOTE.
Org reports a change that open subtasks or boxes block as a message, not an error: that is an
error here, with org's own words."
  (org-with-point-at m
    (org-back-to-heading t)
    (let ((org-log-note-purpose nil)
          (org-blocker-hook (if force nil org-blocker-hook))
          (org-log-note-clock-out nil)
          (said nil))
      (cl-letf* ((orig (symbol-function 'message))
                 ((symbol-function 'message)
                  (lambda (fmt &rest args) (when fmt (push (apply #'format fmt args) said)) (apply orig fmt args))))
        (condition-case err
            (org-todo (if (equal state "none") 'none state))
          (user-error (+endgame--invalid "%s" (error-message-string err)))))
      ;; a repeating task goes back to its open state, so the state alone proves nothing: org's words do
      (when-let* ((blocked (seq-find (lambda (m) (string-match-p "blocked" m)) said)))
        (+endgame--invalid "%s" blocked))
      ;; org queues the note question for a keyboard; a daemon has none, so org is
      ;; asked the same question here and answered with NOTE
      (when (and (not (equal state "none")) (+endgame--state-asks-for-note-p state))
        (save-window-excursion
          (org-add-log-note)
          (with-current-buffer "*Org Note*"
            (insert note)
            (org-store-log-note)))))))

(defun +endgame-todo-json (file line id state &optional note force)
  "Change the heading's TODO keyword to STATE (\"none\" removes it) the way org-todo does.
NOTE answers the note a state like WAIT, HOLD or KILL asks for (refused without
one). FORCE (the calendar deleting an item) overrides the open-subtasks block,
like C-u C-u C-u C-c C-t. A heading with neither :ID: nor :CALDAV_UID: gets an :ID:, so its
handle survives the next edit. Returns {file, line, id, state, change, files}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        (state (string-trim (or state "")))
        (note (let ((n (string-trim (or note "")))) (and (not (string-empty-p n)) n)))
        result)
    (+endgame--saving
      (let ((m (+endgame--locate file line id)))
        (org-with-point-at m
          (let* ((keywords org-todo-keywords-1)
                 (state (cond ((string-empty-p state) (+endgame--invalid "state is required (e.g. DONE, or \"none\")"))
                              ((equal (downcase state) "none") "none")
                              ((member (upcase state) keywords) (upcase state))
                              (t (+endgame--invalid "unknown state \"%s\". States: %s, or \"none\" to remove the keyword"
                                                    state (string-join keywords " ")))))
                 (was (org-get-todo-state))
                 (title (+endgame--title)))
            (when (equal was (and (not (equal state "none")) state))
              (+endgame--invalid "\"%s\" is already %s" title (or was "without a keyword")))
            (when (and (not (equal state "none")) (+endgame--state-asks-for-note-p state) (not note))
              (+endgame--invalid "a task going to %s asks for a note (why it's parked or killed). Pass note" state))
            (+endgame--change-state m state note force)
            (unless (or (org-entry-get nil "ID") (org-entry-get nil "CALDAV_UID"))
              (org-id-get-create))
            (setq result (+endgame--result
                          m `(change . ,(format "%s → %s: %s" (or was "(none)") (or (org-get-todo-state) "(none)") title))))))))
    (+endgame--answer result)))

;;; Dates and priority

(defun +endgame--plan-input (date time end)
  "What org's date analysis reads for DATE (\"YYYY-MM-DD\"), TIME and END (\"HH:MM\"): \"2026-12-01 14:00-15:00\"."
  (unless (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date) (+endgame--invalid "bad date %S (want YYYY-MM-DD)" date))
  (concat date (and time (concat " " time (and end (concat "-" end))))))

(defun +endgame--plan-extras (what repeater warning)
  "Put REPEATER (\"+1w\") and WARNING (\"-3d\") inside the WHAT timestamp on the planning line at point.
Org's planning functions write the date and the time, not these two."
  (let ((extra (string-join (delq nil (list (and repeater (if (string-match-p "\\`[.+]?\\+[0-9]+[hdwmy]\\'" repeater) repeater (+endgame--invalid "bad repeater %S" repeater)))
                                           (and warning (if (string-match-p "\\`-[0-9]+[hdwmy]\\'" warning) warning (+endgame--invalid "bad warning %S" warning)))))
                            " ")))
    (unless (string-empty-p extra)
      (save-excursion
        (forward-line 1)
        (when (re-search-forward (if (eq what 'scheduled) org-scheduled-time-regexp org-deadline-time-regexp) (line-end-position) t)
          (goto-char (match-end 1))
          (when (eq (char-before) ?>) (backward-char 1))
          (insert " " extra))))))

(defun +endgame-plan-json (file line id kind date &optional time end repeater warning)
  "Set the heading's SCHEDULED or DEADLINE (KIND \"scheduled\" or \"deadline\") to DATE (\"YYYY-MM-DD\"),
with TIME and END (\"HH:MM\"), a REPEATER (\"+1w\") and a WARNING (\"-3d\"). DATE nil removes it.
No reschedule note is asked for. Returns {file, line, id, state, files}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        (what (pcase kind ("scheduled" 'scheduled) ("deadline" 'deadline)
                (_ (+endgame--invalid "kind must be scheduled or deadline"))))
        result)
    (+endgame--saving
      (let ((m (+endgame--locate file line id))
            (org-log-reschedule nil)
            (org-log-redeadline nil))
        (org-with-point-at m
          (org-back-to-heading t)
          (if (or (null date) (equal date ""))
              (org-add-planning-info nil nil what)
            (when (and (null time) end) (+endgame--invalid "end needs time"))
            (org-add-planning-info what (+endgame--plan-input date time end))
            (+endgame--plan-extras what repeater warning)))
        (setq result (+endgame--result m))))
    (+endgame--answer result)))

(defun +endgame-priority-json (file line id priority)
  "Set the heading's priority to PRIORITY (\"A\"…); nil or \"\" removes it. Returns {file, line, id, state, files}."
  (let ((inhibit-interaction t)
        (+endgame--saved nil)
        result)
    (+endgame--saving
      (let ((m (+endgame--locate file line id)))
        (org-with-point-at m
          (org-back-to-heading t)
          (if (or (null priority) (equal priority ""))
              (org-priority 'remove)
            (let ((c (string-to-char (upcase priority))))
              (unless (and (= (length priority) 1) (<= org-priority-highest c org-priority-lowest))
                (+endgame--invalid "priority must be %c to %c, or nothing to remove it" org-priority-highest org-priority-lowest))
              (org-priority c))))
        (setq result (+endgame--result m))))
    (+endgame--answer result)))

;;; What the apps show

(defun +endgame-keywords-json ()
  "The keywords org knows, for the phone's pickers: {sequences: [{todo, done}], keywords:
[{keyword, done, needsNote}], priorities: {highest, lowest, default}}."
  (let ((inhibit-interaction t))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (let ((done org-done-keywords))
        (+endgame--json
         `((sequences . ,(vconcat (mapcar (lambda (set)
                                            `((todo . ,(vconcat (seq-remove (lambda (k) (member k done)) set)))
                                              (done . ,(vconcat (seq-filter (lambda (k) (member k done)) set)))))
                                          org-todo-sets)))
           (keywords . ,(vconcat (mapcar (lambda (k)
                                           `((keyword . ,k)
                                             (done . ,(if (member k done) t :json-false))
                                             (needsNote . ,(if (+endgame--state-asks-for-note-p k) t :json-false))))
                                         org-todo-keywords-1)))
           (priorities . ((highest . ,(char-to-string org-priority-highest))
                          (lowest . ,(char-to-string org-priority-lowest))
                          (default . ,(char-to-string org-priority-default))))))))))

(provide '+endgame-todo)
;;; +endgame-todo.el ends here

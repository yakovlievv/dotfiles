;;; endgame-todo-test.el --- tests for +endgame-todo.el -*- lexical-binding: t; -*-
;;
;; Runs without Doom, in a throwaway vault, against org itself:
;;
;; emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org \
;;   -L ~/.config/emacs/.local/straight/build-31.1/org-contrib \
;;   -l ~/.config/doom/tests/endgame-todo-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'org-checklist)

(setq org-id-locations-file (make-temp-file "endgame-todo-test-ids")
      org-id-track-globally nil)

(load (expand-file-name "../+endgame-capture.el" (file-name-directory (or load-file-name buffer-file-name))) nil t)
(load (expand-file-name "../+endgame-todo.el" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar +endgame-todo-test-config (expand-file-name "~/org/roam/config/doom-config.org")
  "The literate config, whose habits block says a habit can be ticked with open steps.")

(defmacro after! (feature &rest body) `(with-eval-after-load ',feature ,@body))
(with-temp-buffer
  (insert-file-contents +endgame-todo-test-config)
  (when (re-search-forward "^#\\+name: habits\n#\\+begin_src emacs-lisp.*\n" nil t)
    (let ((beg (point)))
      (re-search-forward "^#\\+end_src")
      (eval (car (read-from-string (concat "(progn " (buffer-substring beg (match-beginning 0)) "\n)"))) t))))

(defvar +endgame-todo-test-dir nil)

(defmacro +endgame-todo-test--with-vault (text &rest body)
  "Run BODY with a vault holding roam/t.org with TEXT. The settings of the real config that matter here."
  (declare (indent 1))
  `(let* ((+endgame-todo-test-dir (file-name-as-directory (make-temp-file "endgame-todo-test" t)))
          (+endgame-vault-dir +endgame-todo-test-dir)
          (org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "STRT(s!)" "WAIT(w@/!)" "HOLD(h@/!)" "|" "DONE(d!)" "KILL(k@)")))
          (org-log-into-drawer t)
          (org-log-done 'time)
          (org-log-repeat 'time)
          (org-enforce-todo-dependencies t)
          (org-enforce-todo-checkbox-dependencies t)
          (org-extend-today-until 5)
          (file (expand-file-name "roam/t.org" +endgame-todo-test-dir)))
     (make-directory (file-name-directory file) t)
     (with-temp-file file (insert ,text))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b) (string-prefix-p (file-truename +endgame-todo-test-dir) (file-truename (buffer-file-name b))))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory +endgame-todo-test-dir t))))

(defun +endgame-todo-test--text ()
  (with-temp-buffer (insert-file-contents (expand-file-name "roam/t.org" +endgame-todo-test-dir)) (buffer-string)))

(defun +endgame-todo-test--json (s) (json-parse-string s :object-type 'alist :array-type 'list :false-object :false))

(defun +endgame-todo-test--refused (regexp thunk)
  (let ((e (should-error (funcall thunk))))
    (should (string-match-p (concat "\\[invalid\\].*" regexp) (error-message-string e)))))

(ert-deftest +endgame-todo-done-closes-logs-and-pins-an-id ()
  (+endgame-todo-test--with-vault "* TODO call the bank\n"
    (let ((r (+endgame-todo-test--json (+endgame-todo-json file 1 nil "done"))))
      (should (equal (alist-get 'state r) "DONE"))
      (should (equal (append (alist-get 'files r) nil) '("roam/t.org")))
      (should (alist-get 'id r)))
    (let ((text (+endgame-todo-test--text)))
      ;; what org writes for a plain close: CLOSED (org-log-done 'time); the id goes in after it
      (should (string-match-p "^\\* DONE call the bank\nCLOSED: \\[[^]]+\\]\n:PROPERTIES:\n:ID: +[-0-9A-Fa-f]+" text)))
    ;; back: CLOSED goes
    (+endgame-todo-json file 1 nil "TODO")
    (should-not (string-match-p "CLOSED" (+endgame-todo-test--text)))))

(ert-deftest +endgame-todo-a-note-state-asks-for-its-note ()
  (+endgame-todo-test--with-vault "* TODO call the bank\n* TODO other\n"
    (+endgame-todo-test--refused "asks for a note" (lambda () (+endgame-todo-json file 1 nil "WAIT")))
    (+endgame-todo-test--refused "asks for a note" (lambda () (+endgame-todo-json file 1 nil "KILL" "  ")))
    (+endgame-todo-json file 1 nil "WAIT" "waiting for the callback")
    (let ((text (+endgame-todo-test--text)))
      (should (string-match-p "^\\* WAIT call the bank\n:PROPERTIES:" text))
      (should (string-match-p ":LOGBOOK:\n- State \"WAIT\" +from \"TODO\" +\\[[^]]+\\] \\\\\\\\\n  waiting for the callback\n:END:" text)))
    ;; KILL with its note, closed
    (+endgame-todo-json file nil (alist-get 'id (+endgame-todo-test--json (+endgame-todo-json file 1 nil "KILL" "not needed"))) "TODO")
    (should (string-match-p "^\\* TODO call the bank" (+endgame-todo-test--text)))))

(ert-deftest +endgame-todo-refuses-unknown-or-unchanged-states ()
  (+endgame-todo-test--with-vault "* TODO a\n* DONE b\n"
    (+endgame-todo-test--refused "unknown state \"NOPE\"" (lambda () (+endgame-todo-json file 1 nil "NOPE")))
    (+endgame-todo-test--refused "already TODO" (lambda () (+endgame-todo-json file 1 nil "TODO")))
    (+endgame-todo-test--refused "state is required" (lambda () (+endgame-todo-json file 1 nil "")))
    (+endgame-todo-test--refused "no heading" (lambda () (+endgame-todo-json file 99 nil "DONE")))
    ;; "none" removes the keyword
    (+endgame-todo-json file 1 nil "none")
    (should (string-match-p "^\\* a$" (+endgame-todo-test--text)))))

(ert-deftest +endgame-todo-a-repeating-habit-repeats-and-clears-its-boxes ()
  (+endgame-todo-test--with-vault
      (concat "* TODO stretch [1/2]\nSCHEDULED: <2026-11-20 Fri .+1d>\n"
              ":PROPERTIES:\n:STYLE: habit\n:RESET_CHECK_BOXES: t\n:END:\n- [X] a\n- [ ] b\n")
    (let ((r (+endgame-todo-test--json (+endgame-todo-json file 1 nil "DONE"))))
      (should (equal (alist-get 'state r) "TODO")))
    (let ((text (+endgame-todo-test--text)))
      (should (string-match-p "^\\* TODO stretch \\[0/2\\]" text))
      (should (string-match-p ":LAST_REPEAT: " text))
      (should-not (string-match-p "CLOSED" text))
      (should-not (string-match-p "\\[X\\]" text))
      (should-not (string-match-p "<2026-11-20" text)))))

(ert-deftest +endgame-todo-open-subtasks-block-it-unless-forced ()
  (+endgame-todo-test--with-vault "* TODO parent [0/1]\n** TODO child\n"
    (+endgame-todo-test--refused "blocked" (lambda () (+endgame-todo-json file 1 nil "DONE")))
    (should (string-match-p "^\\* TODO parent" (+endgame-todo-test--text)))
    (+endgame-todo-json file 1 nil "KILL" "deleted in the calendar" t)
    (should (string-match-p "^\\* KILL parent" (+endgame-todo-test--text)))))

(ert-deftest +endgame-todo-a-done-child-counts-in-its-parent ()
  (+endgame-todo-test--with-vault "* TODO parent [0/2]\n** TODO one\n** TODO two\n"
    (+endgame-todo-json file 2 nil "DONE")
    (should (string-match-p "^\\* TODO parent \\[1/2\\]" (+endgame-todo-test--text)))))

(ert-deftest +endgame-plan-sets-moves-and-removes-dates ()
  (+endgame-todo-test--with-vault "* TODO write the report\n"
    (+endgame-plan-json file 1 nil "scheduled" "2026-12-01" "14:00" "15:00" "+1w" nil)
    (should (string-match-p "^\\* TODO write the report\nSCHEDULED: <2026-12-01 [A-Za-z]+ 14:00-15:00 \\+1w>$" (+endgame-todo-test--text)))
    (+endgame-plan-json file 1 nil "deadline" "2026-12-10" nil nil nil "-3d")
    (should (string-match-p "DEADLINE: <2026-12-10 [A-Za-z]+ -3d>" (+endgame-todo-test--text)))
    (should (string-match-p "SCHEDULED: <2026-12-01" (+endgame-todo-test--text)))
    ;; a new date replaces, without a reschedule note
    (+endgame-plan-json file 1 nil "scheduled" "2026-12-02")
    (let ((text (+endgame-todo-test--text)))
      (should (string-match-p "SCHEDULED: <2026-12-02 [A-Za-z]+>" text))
      (should-not (string-match-p "Rescheduled\\|LOGBOOK" text)))
    ;; removing
    (+endgame-plan-json file 1 nil "scheduled" nil)
    (should-not (string-match-p "SCHEDULED" (+endgame-todo-test--text)))
    (should (string-match-p "DEADLINE" (+endgame-todo-test--text)))
    (+endgame-todo-test--refused "kind must be" (lambda () (+endgame-plan-json file 1 nil "nope" "2026-12-02")))))

(ert-deftest +endgame-priority-sets-and-removes ()
  (+endgame-todo-test--with-vault "* TODO a\n* TODO [#B] b\n"
    (+endgame-priority-json file 1 nil "a")
    (should (string-match-p "^\\* TODO \\[#A\\] a$" (+endgame-todo-test--text)))
    (+endgame-priority-json file 2 nil "")
    (should (string-match-p "^\\* TODO b$" (+endgame-todo-test--text)))
    (+endgame-todo-test--refused "priority must be" (lambda () (+endgame-priority-json file 1 nil "Z")))
    (+endgame-todo-test--refused "priority must be" (lambda () (+endgame-priority-json file 1 nil "AB")))))

(ert-deftest +endgame-keywords-json-says-what-org-knows ()
  (+endgame-todo-test--with-vault ""
    (let* ((k (+endgame-todo-test--json (+endgame-keywords-json)))
           (words (mapcar (lambda (x) (alist-get 'keyword x)) (alist-get 'keywords k)))
           (wait (cl-find "WAIT" (alist-get 'keywords k) :key (lambda (x) (alist-get 'keyword x)) :test #'equal)))
      (should (member "NEXT" words))
      (should (eq (alist-get 'needsNote wait) t))
      (should (eq (alist-get 'done wait) :false))
      (should (equal (alist-get 'todo (car (alist-get 'sequences k))) '("TODO" "NEXT" "STRT" "WAIT" "HOLD")))
      (should (equal (alist-get 'done (car (alist-get 'sequences k))) '("DONE" "KILL")))
      (should (equal (alist-get 'highest (alist-get 'priorities k)) "A")))))

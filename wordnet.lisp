;;;-*- Mode: common-lisp; syntax: common-lisp; package: wordnet; base: 10 -*-
;;;
;;; IT Program Project in Japan: 
;;;    Building Operation-Support System for Large-scale System using IT
;;;
;;; This code is modified from Ruml's original work for Allegro7.0 modern and WordNet2.0
;;; by Seiji Koide at Galaxy Express Corporation, Japan,
;;;
;;; 1. Installation of WordNet2.0 results setting user environment variable WNHOME.
;;;    However, this system checks system environmnet variable WNHOME. So, a user should
;;;    copy the user environment variable to the system environment variable.
;;;
;;; History
;;; -------
;;; 2005.01.21    File obtained from Ruml's web site
;;;
;;;======================================================================================
;; This is:
;;  $Source: /home/cellar/shieber/ruml/projects/lexical/wordnet/src/RCS/wordnet.lisp,v $   
;;  $Revision: 1.6 $    

;; an interface to wordnet, a semantic network for words from Princeton.
;;
;; The main entry point is get-word.  From there, just use the normal
;; structure accessors.
;;
;; Wheeler Ruml (ruml@eecs.harvard.edu)

(defpackage wordnet
  (:use common-lisp))
(in-package wordnet)

;;;
;;; Utils
;;;

(eval-when (:execute :load-toplevel :compile-toplevel)
(defun str (&rest args)
  "makes a string from printed representations of all of its arguments"
  (declare (optimize (speed 3) (safety 1) (debug 0)))
  (let ((*print-circle* nil))
    (format nil "~{~A~}" args)))

(defmacro with-gensyms (syms &body body)
  "set the value of each symbol in SYMS to a unique gensym"
  `(let ,(mapcar #'(lambda (s)
		     `(,s (gensym)))
	  syms)
     ,@body))
)


(defun spaced-str (first &rest args)
  "makes a string from all its arguments, inserting spaces between items"
  (let ((*print-circle* nil)
        (*print-level* cl:nil)
        (*print-length* cl:nil))
    (format nil "~A~{ ~A~}" first args)))

(defun first-n-list (list &optional (n 1))
  "Returns a new list containing the first N elements of LIST."
  (cond ((<= n 0) nil)
	((endp list) nil)
	(t (cons (first list)
		 (first-n-list (rest list) (1- n))))))

(defun groups-of (n list)
  "returns a list of subsequences of LIST of length <= N"
  (assert (> n 0))
  (when list
    (cons (first-n list n)
          (groups-of n (nthcdr n list)))))

(defun split-seq-on (str &optional (ch #\Space))
  "returns a list of strings formed by breaking STR at every occurance
of CH (which is not included).  Works for any sequence, not just strings,
but optimized for vectors."
  (when str
    (do* ((prev-pos 0 (1+ next-pos))
	  (next-pos (position ch str)
		    (position ch str :start prev-pos))
	  (stuff (list (subseq str 0 next-pos))
		 (cons (subseq str prev-pos next-pos)
		       stuff)))
         ((null next-pos) (nreverse stuff)))))

(defun skip-line (strm)
  "reads through the next #\Newline."
  (declare (optimize (speed 3) (safety 1) (debug 0))
           (type stream strm))
  (loop
    (let ((ch (read-char strm nil nil)))
      (declare (dynamic-extent ch))
      (when (eq ch #\Newline)
        (return)))))

(defun first-n (seq &optional (n 1))
  "Returns a new sequence containing the first N elements of SEQ."
  (etypecase seq
    (vector (subseq seq 0 (min n (length seq))))
    (list (first-n-list seq n))))

(defun seq-starts-as (prefix-str text)
  "returns non-nil iff TEXT starts as STR"
  (let ((diff-pos (mismatch prefix-str text)))
    (or (null diff-pos)
        (>= diff-pos (length prefix-str)))))

(defun split-seq-using (str &optional (ch #\Space))
  "returns a list of strings.  Ignores multiple delimiters."
  (when str
    (do* ((prev-pos (position ch str :test-not #'eql)
		    (position ch str :test-not #'eql :start next-pos))
	  (next-pos (when prev-pos (position ch str :start prev-pos))
		    (when prev-pos (position ch str :start prev-pos)))
	  (stuff (when prev-pos
		   (list (subseq str prev-pos next-pos)))
		 (if prev-pos
		     (cons (subseq str prev-pos next-pos)
			   stuff)
		   stuff)))
	((null next-pos) (nreverse stuff)))))

(defmacro with-list-split-after (n (first-part second-part) list &body body)
  "executes BODY with FIRST-PART bound to the first N elements of LIST
and SECOND-PART bound to the rest"
  (with-gensyms (num l)
    `(let* ((,num ,n)
            (,l ,list)
            (,first-part (first-n ,l ,num))
            (,second-part (nthcdr ,num ,l)))
       ,@body)))

(defun map-groups-of (n func list)
  "MAPCARs FUNC over groups of N elements from LIST"
  (let ((l (groups-of n list)))
    (mapcar #'(lambda (args)
		(apply func args))
	    l)))

;;;;;;;;;;;;;;; data structures for wordnet information ;;;;;;;;;;;

(defclass word ()
  ((pos :initarg :pos :accessor word-pos)
   (string :initarg :string :accessor word-string)
   (senses :initform :placeholder :accessor word-private-senses)
   (dict-sense-count :initform :placeholder :accessor word-private-dict-sense-count)))


(defstruct (word-sense (:conc-name word-sense-private-)
                       (:print-function pp-word-sense))
  synset								
  word
  (order-in-word :placeholder)	; from index
  (order-in-synset :placeholder)	; from data
  (pointers :placeholder)		; from data
  (lexicographer-id :placeholder)	; from data
  (adjective-syntax-marker :placeholder) ; optional, from data
  (verb-sentence-templates :placeholder)) ; optional, from data

#|
(defstruct (synset (:conc-name synset-private-)
	    (:print-function pp-synset))
  pos
  file-offset
  (senses :placeholder)			; from data
  (pointers :placeholder)		; from data
  (lex-file-num :placeholder)		; from data
  (gloss :placeholder))			; from data
|#
(defclass synset ()
  ((pos :initarg :pos :accessor synset-pos)
   (file-offset :initarg :file-offset :accessor synset-file-offset)
   (senses :initform :placeholder :accessor synset-private-senses)
   (pointers :initform :placeholder :accessor synset-private-pointers)
   (lex-file-num :initform :placeholder :accessor synset-private-lex-file-num)
   (gloss :initform :placeholder :accessor synset-private-gloss)))

(defun synset-p (instance)
  (typep instance 'synset))

(defstruct pointer
  relation
  source
  dest)


;;;;;;;;;;;;;;; macros for accessors that auto-load ;;;;;;;;;;;

(defmacro define-public-accessors (struct (&optional (private-prefix
						      (str struct '#:-private-)))
				   &rest slots)
  "given a symbol naming a struct, and the symbols naming its slots,
defines accessor macros which look like the ones DEFSTRUCT would have defined.
The assumption is that the struct has been defined with the :conc-name
option, using `-private' as an additional component in the names of the
actual accessors defined by DEFSTRUCT.  So the macros defined by this macro
allow one to use accessor functions that don't have `-private' in their
names.  I use this to define accessors for those slots in the structure
that I don't want to have special auto-loading accessors for."
  `(progn
     ,@(mapcar #'(lambda (slot)
		   `(defmacro ,(intern (str struct "-" slot)) (object)
		      `(,',(intern (str private-prefix slot)) ,object)))
         slots)))

(defmacro define-loading-accessor (name accessor-name loader)
  "defines an accessor function named NAME which will use the function
LOADER to get the data for a structure's slot if the accessor named by
ACCESSOR-NAME returns :placeholder."
  `(defun ,name (object)
     (when (eq (,accessor-name object)
	       :placeholder)
       ;; (format t "~&~A failed, calling ~A.~%" ',name ',loader)
       (unless (,loader object)
	 (error "failure loading")))
     (,accessor-name object)))


(defmacro define-loading-accessors (struct (loader
					    &optional (private-prefix
						       (str struct
							    '#:-private-)))
				    &rest slots)
  "a macro for defining multiple loading accessors."
  `(progn
     ,@(mapcar #'(lambda (slot)
		   `(define-loading-accessor
			,(intern (str struct "-" slot))
			,(intern (str private-prefix slot))
		      ,loader))
	       slots)))


(defmacro define-public-setfs (struct (&optional (private-prefix
						  (str struct
						       '#:-private-)))
			       &rest slots)
  "defines setfs for the SLOTS in STRUCT."
  `(progn
     ,@(mapcar #'(lambda (slot)
		   `(defun (setf ,(intern (str struct "-" slot)))
			(new-val object)
		      (setf (,(intern (str private-prefix slot)) object)
			new-val)))
	       slots)))


;;;;;;;;;;;;;;; define accessor functions ;;;;;;;;;;;


(define-loading-accessors word (load-word) senses dict-sense-count)
#|
(progn (define-loading-accessor word-senses word-private-senses load-word)
       (define-loading-accessor word-dict-sense-count word-private-dict-sense-count
         load-word))
(defun word-senses (object)
  (when (eq (word-private-senses object) :placeholder)
    (unless (load-word object) (error "failure loading")))
  (word-private-senses object))
(defun word-dict-sense-count (object)
  (when (eq (word-private-dict-sense-count object) :placeholder)
    (unless (load-word object) (error "failure loading")))
  (word-private-dict-sense-count object))
|#

(define-public-setfs word () senses dict-sense-count)
#|
(progn (defun (setf word-senses) (new-val object)
         (setf (word-private-senses object) new-val))
       (defun (setf word-dict-sense-count) (new-val object)
         (setf (word-private-dict-sense-count object) new-val)))
|#

(define-public-accessors word-sense () synset word)
#|
(progn (defmacro word-sense-synset (object)
         (excl::bq-list 'word-sense-private-synset object))
       (defmacro word-sense-word (object)
         (excl::bq-list 'word-sense-private-word object)))
|#

(define-loading-accessors word-sense (load-index-word-sense) order-in-word)
#|
(progn (define-loading-accessor word-sense-order-in-word
           word-sense-private-order-in-word load-index-word-sense))
(defun word-sense-order-in-word (object)
  (when (eq (word-sense-private-order-in-word object) :placeholder)
    (unless (load-index-word-sense object) (error "failure loading")))
  (word-sense-private-order-in-word object))
|#

(define-loading-accessors word-sense (load-data-word-sense)
  order-in-synset pointers lexicographer-id
  adjective-syntax-marker verb-sentence-templates)
#|
(progn (define-loading-accessor word-sense-order-in-synset
         word-sense-private-order-in-synset load-data-word-sense)
       (define-loading-accessor word-sense-pointers word-sense-private-pointers
         load-data-word-sense)
       (define-loading-accessor word-sense-lexicographer-id
         word-sense-private-lexicographer-id load-data-word-sense)
       (define-loading-accessor word-sense-adjective-syntax-marker
         word-sense-private-adjective-syntax-marker load-data-word-sense)
       (define-loading-accessor word-sense-verb-sentence-templates
           word-sense-private-verb-sentence-templates load-data-word-sense))
(defun word-sense-order-in-synset (object)
  (when (eq (word-sense-private-order-in-synset object) :placeholder)
    (unless (load-data-word-sense object) (error "failure loading")))
  (word-sense-private-order-in-synset object))
(defun word-sense-pointers (object)
  (when (eq (word-sense-private-pointers object) :placeholder)
    (unless (load-data-word-sense object) (error "failure loading")))
  (word-sense-private-pointers object))
|#

(define-public-setfs word-sense () synset word
		     order-in-word order-in-synset pointers lexicographer-id
		     adjective-syntax-marker verb-sentence-templates)
#|
(progn (defun (setf word-sense-synset) (new-val object)
         (setf (word-sense-private-synset object) new-val))
       (defun (setf word-sense-word) (new-val object)
         (setf (word-sense-private-word object) new-val))
       (defun (setf word-sense-order-in-word) (new-val object)
         (setf (word-sense-private-order-in-word object) new-val))
       (defun (setf word-sense-order-in-synset) (new-val object)
         (setf (word-sense-private-order-in-synset object) new-val))
       (defun (setf word-sense-pointers) (new-val object)
         (setf (word-sense-private-pointers object) new-val))
       (defun (setf word-sense-lexicographer-id) (new-val object)
         (setf (word-sense-private-lexicographer-id object) new-val))
       (defun (setf word-sense-adjective-syntax-marker) (new-val object)
         (setf (word-sense-private-adjective-syntax-marker object) new-val))
       (defun (setf word-sense-verb-sentence-templates) (new-val object)
         (setf (word-sense-private-verb-sentence-templates object) new-val)))
|#

;(define-public-accessors synset () pos file-offset)
#|
(progn (defmacro synset-pos (object) (excl::bq-list 'synset-private-pos object))
       (defmacro synset-file-offset (object)
         (excl::bq-list 'synset-private-file-offset object)))
|#

(define-loading-accessors synset (load-synset)
  senses pointers lex-file-num gloss)
#|
(progn (define-loading-accessor synset-senses synset-private-senses load-synset)
       (define-loading-accessor synset-pointers synset-private-pointers load-synset)
       (define-loading-accessor synset-lex-file-num synset-private-lex-file-num
         load-synset)
       (define-loading-accessor synset-gloss synset-private-gloss load-synset))
(defun synset-senses (object)
  (when (eq (synset-private-senses object) :placeholder)
    (unless (load-synset object) (error "failure loading")))
  (synset-private-senses object))
|#

;(define-public-setfs synset () pos file-offset
;  senses pointers lex-file-num gloss)
(define-public-setfs synset () 
  senses pointers lex-file-num gloss)
#|
(progn (defun (setf synset-pos) (new-val object)
         (setf (synset-private-pos object) new-val))
       (defun (setf synset-file-offset) (new-val object)
         (setf (synset-private-file-offset object) new-val))
       (defun (setf synset-senses) (new-val object)
         (setf (synset-private-senses object) new-val))
       (defun (setf synset-pointers) (new-val object)
         (setf (synset-private-pointers object) new-val))
       (defun (setf synset-lex-file-num) (new-val object)
         (setf (synset-private-lex-file-num object) new-val))
       (defun (setf synset-gloss) (new-val object)
         (setf (synset-private-gloss object) new-val)))
|#

;;;;;;;;;;;;;;; pretty printing ;;;;;;;;;;;


(defun pp-word (word &optional (stream t) depth)
  (declare (ignore depth))
  (format stream "#<~S a ~A with ~A sense~:P>"
	  (word-string word) (word-pos word)
	  (if (eq (word-private-senses word) :placeholder)
	      "?" (length (word-senses word)))))


(defun pp-word-sense (sense &optional (stream t) depth)
  (declare (ignore depth))
  (format stream "#<SENSE of ~S in ~A:~A (~D ptr~:P)>"
	  (word-string (word-sense-word sense))
	  (synset-pos (word-sense-synset sense))
	  (synset-file-offset (word-sense-synset sense))
	  (if (eq (word-sense-private-pointers sense) :placeholder)
	      "?" (length (word-sense-pointers sense)))))
#|
(defun pp-synset (synset &optional (stream t) depth)
  (declare (ignore depth))
  (format stream "#<~S SYNSET of~{ ~S~} (~D ptr~:P)>"
	  (synset-pos synset)
	  (mapcar #'word-string
		  (mapcar #'word-sense-word
			  (synset-senses synset)))
	  (if (eq (synset-private-pointers synset) :placeholder)
	      "?" (length (synset-pointers synset)))))
|#
;;;;;;;;;;;;;;; globals ;;;;;;;;;;;

(defconstant +all-pos+ '(:noun :verb :adjective :adverb))

(defparameter *wnhome*
    (or #+:allegro (sys:getenv "WNHOME")
        #+:unix "/usr/share/wordnet/"
        #+:mswindow "C:\\Program Files\\WordNet\\2.0"))
(defparameter *wnsearchdir*
    (or #+:allegro (sys:getenv "WNSEARCHDIR")
        #+:unix "/usr/share/wordnet/"
        #+:mswindow (concatenate 'string *wnhome* "\\dict")))
(defconstant +wordnet-path-default+
;    "~/library/data/wordnet/dict/*"
  #+:unix "/usr/share/wordnet/"
  #+:mswindow (concatenate 'string *wnhome* "\\dict")
  )

(defconstant +approx-hash-table-size+ 50000)

(defun load-top-synsets ()
  "loads the roots of the hierarchy"
  )

(defun load-verb-sentence-templates ()
  "loads the sentence templates for verbs"
  )

(defparameter *top-synsets*
    (load-top-synsets))

(defparameter *verb-sentence-templates*
    (load-verb-sentence-templates))

;;;;;;;;;;;;;;; words ;;;;;;;;;;;

(defvar *word-cache*				
    (make-hash-table :test #'equal :size +approx-hash-table-size+)
  "string, pos -> word")

(defun get-word (string &optional (pos :noun)
                        (check-wordnet t))
  "returns word corresponding to string, from cache or file"
  (let* ((lower (string-downcase string))
         (key (cons pos lower)))
    (or (gethash key *word-cache*)
        (let ((word (make-instance 'word :pos pos :string string)))
          (when (or (eq check-wordnet nil)
                    (load-word word))
            ;; (format t "~&Adding new word '~A'.~%" string)
            (setf (gethash key *word-cache*)
              word)
            word)))))

(defun load-word (word)
  (load-word-from-index-entry word
                              (get-index-entry (string-downcase
                                                (word-string word))
                                               (word-pos word))))

(defun get-index-entry (string pos)
  ;(format t "~&Getting index entry for ~A '~A'.~%" pos string)
  (with-open-file (stream (pos-index-file pos) :direction :input)
    (let ((entry-start (str string " "))
          (pos-position (1+ (length string))))
      (let ((entry (binary-search-lines stream entry-start)))
        (when entry
          (unless (eq (pos-from-symbol (subseq entry pos-position
                                               (1+ pos-position)))
                      pos)
            (error "Bad pos symbol in index line"))
          (split-seq-using (subseq entry (+ pos-position
                                            2))))))))


;; could be sped up by having a hash table for each filename and mod date
;; encountered in which were stored (by try-offset) the first 8 entries
;; read in every search.
;; This would provide smaller initial range.
;;
;; since morphology code tends to do lots of probes in the same area,
;; it might also be useful to save the complete results of the last 5
;; searches for each file.

(defun binary-search-lines (stream entry-start)
  "uses a binary search to find the line in the file to which stream is
opened that begins with entry-start.  Obviously, lines in the file must
be sorted.  They need not all be the same length."
  (let ((start 0)
        (end (file-length stream))
        (num-reads 0))
    (loop
      (if (> start end)
          (progn
            (format t "*** In ~D reads, failed on: ~A~%"
              num-reads entry-start)
            (return nil))
        (let ((try-offset (floor (+ start end) 2)))
          (multiple-value-bind
                (entry actual-offset)
              (next-entry-from-offset stream try-offset)
            (incf num-reads)
            ;(format t "~D - ~D > ~D = ~D: ~A~%"
            ;  start end try-offset actual-offset (first-n entry 10))
            (cond ((or (null entry)
                       (> actual-offset end))
                   ;; try-offset was in middle of last entry; look earlier
                   (setf end (1- try-offset)))
                  ((seq-starts-as entry-start entry)
                   ;; got it!
                   (format t "*** In ~D reads, got: ~A~%" num-reads (first-n entry 20))
                   (return entry))
                  ((string> entry entry-start)
                   ;; look earlier
                   (setf end (1- try-offset)))
                  ((string< entry entry-start)
                   ;; look later
                   (setf start (+ actual-offset (length entry))))
                  (t (error "bad string comparisons")))))))))


;;(defun end-of-preamble (stream)
;;  (do ((offset 0 (file-position stream)))
;;	  ((not (seq-starts-as "  " (read-line stream)))
;;	   offset)))


(defun next-entry-from-offset (stream offset)
  "returns the next complete line after offset in stream, and the
position of its first character"
  ;; find line from offset
  (cond ((<= offset 0)
         (file-position stream 0))
        (t (file-position stream (1- offset))
           (skip-line stream)
           ))
  ;; record position and read line
  (let ((actual (file-position stream)))
    (values (read-line stream nil nil)
            actual)))


(defun load-word-from-index-entry (word entry-tokens)
  (when entry-tokens
    (destructuring-bind
	(sense-count num-pointers . rest-tokens)
	entry-tokens
      (setf (word-dict-sense-count word)
        (parse-integer sense-count))
      (destructuring-bind
          (num-synsets TAGSENSE-CNT . synsets)
          (nthcdr (parse-integer num-pointers) rest-tokens)
        (declare (ignore TAGSENSE-CNT))
        (unless (= (parse-integer num-synsets) (length synsets))
          (error "Bad num-pointers or num-synsets"))
        (setf (word-senses word)
          (mapcar (make-sense-loader word) synsets))))
    word))


(defun make-sense-loader (word)
  (let ((counter 0))
    #'(lambda (offset)
	(let* ((pos (word-pos word))
	       (sense (get-word-sense word
				      (get-synset pos
						  (parse-integer offset)))))
	  (incf counter)
	  (setf (word-sense-order-in-word sense)
	    counter)
	  sense))))


;;;;;;;;;;;;;;; word senses ;;;;;;;;;;;


(defvar *word-sense-cache*
    (make-hash-table :test #'equal :size +approx-hash-table-size+)
  "word, synset -> word-sense")


(defun get-word-sense (word synset)
  (let ((key (cons word synset)))
    (or (gethash key *word-sense-cache*)
	(let ((sense (make-word-sense :word word
				      :synset synset)))
	  ;; (format t "~&Adding new sense from '~A' in '~A:~A'.~%"
	  ;;	  (word-string word) (synset-pos synset)
	  ;;	  (synset-file-offset synset))
	  (setf (gethash key *word-sense-cache*)
	    sense)
	  sense))))


;; will be called if someone calls word-sense-order-in-word on a
;; word-sense that was created via a data file
(defun load-index-word-sense (sense)
  ;; loading the sense's word will have the intended effect
  (load-word (word-sense-word sense)))


(defun load-data-word-sense (sense)
  ;; loading the sense's word will have the intended effect
  (load-synset (word-sense-synset sense)))


;;;;;;;;;;;;;;; synsets ;;;;;;;;;;;


(defvar *synset-cache*
    (make-hash-table :test #'equal :size +approx-hash-table-size+)
  "pos, offset -> synset")


(defun get-synset (pos offset)
  (let ((key (cons pos offset)))
    (or (gethash key *synset-cache*)
	(let ((synset (make-instance 'synset :pos pos :file-offset offset)))
	  ;; (format t "~&Adding new synset '~A:~A'.~%" pos offset) 
	  (setf (gethash key *synset-cache*)
	    synset)
	  synset))))

(defun load-synset (synset)
  (load-synset-from-data-entry synset
                               (get-data-entry (synset-file-offset synset)
                                               (synset-pos synset))))

(defun get-data-entry (offset pos)
  ;(format t "~&Getting data entry for synset '~A:~A'.~%" pos offset)
  (with-open-file (stream (pos-data-file pos) :direction :input)
    (file-position stream offset)
    (let ((line (read-line stream t)))
      (destructuring-bind
	  (this-offset .  tokens) (split-seq-using line)
	(cond ((/= (parse-integer this-offset)
		   offset)
	       (error "offset in data file not file position"))
	      ((not (eq (pos-from-symbol (second tokens))
			pos))
	       (error "bad synset pos in: ~S" tokens))
	      (t tokens))))))


(defun load-synset-from-data-entry (synset tokens)
  ;(format t "~&Loading synset from entry ~A with ~%  ~A'.~%" synset tokens)
  (destructuring-bind
      (file-num pos num-senses . senses-and-more) tokens
    (declare (ignore pos))
    (setf (synset-lex-file-num synset)
      (parse-integer file-num))
    (setf (synset-senses synset) '())
    (setf (synset-pointers synset) '())
    (with-list-split-after (* (parse-integer num-senses :radix 16)
                              2)
      (sense-stuff pointers-and-more) senses-and-more
      (map-groups-of 2 (make-synset-sense-loader synset)
                     sense-stuff)
      (with-list-split-after (* (parse-integer (first pointers-and-more))
                                4)
        (pointer-stuff rest) (rest pointers-and-more)
        (when (eq (pos-from-symbol (third pointer-stuff)) :noun)
          (map-groups-of 4 (make-pointer-loader synset)
                         pointer-stuff)
          (when (eq (synset-pos synset) :verb)
            (with-list-split-after (* (parse-integer (first rest))
                                      3)
              (frame-stuff gloss-stuff) (rest rest)
              (declare (ignore frame-stuff))
              ;(map-groups-of 3 (make-frame-loader synset) frame-stuff)
              (setf rest gloss-stuff)))
          (setf (synset-gloss synset)
            (if rest
                (spaced-str (rest rest))
              "<no gloss in file>"))))))
    synset)


(defun make-synset-sense-loader (synset)
  (let ((counter 0))
    #'(lambda (string id)
        (multiple-value-bind
              (adj-marker base-string) (get-adj-marker string)
          (let* ((word (get-word base-string (synset-pos synset) nil))
                 (sense (get-word-sense word synset)))
            ;; reset word-string from mixed-case in data
            (setf (word-string word)
              base-string)
            (incf counter)
            (setf (word-sense-order-in-synset sense)
              counter)
            (setf (word-sense-lexicographer-id sense)
              (parse-integer id :radix 16))
            (setf (word-sense-pointers sense)
              '())
            (setf (word-sense-adjective-syntax-marker sense)
              adj-marker)
            (setf (word-sense-verb-sentence-templates sense)
              '())
            ;; perhaps this should add to end, to preserve file order?
            (push sense (synset-senses synset)))))))

(defun get-adj-marker (string)
  (let ((parts (split-seq-on string #\()))
    (values (cdr (assoc (second parts) '(("p)" . :predicate-position)
                                         ("a)" . :prenominal-position)
                                         ("ip)" . :postnominal-position))
                        :test #'equal))
            (first parts))))

(defun make-pointer-loader (synset)
  #'(lambda (relation target-offset pos which)
      (let ((source (get-object (parse-integer which :end 2 :radix 16)
                                synset))
            (target (get-object (parse-integer which :start 2 :radix 16)
                                (get-synset (pos-from-symbol pos)
                                            (parse-integer target-offset)))))
        (let ((ptr (make-pointer :relation
                                 (relation-from-symbol relation
                                                       (synset-pos synset))
                                 :source source :dest target)))
          (if (synset-p source)
              (push ptr (synset-pointers  source))
            (push ptr (word-sense-pointers source)))))))

(defun get-object (num synset)
  (cond ((= num 0) synset)
        ((> num 0) (find num (synset-senses synset)
                         :key #'word-sense-order-in-synset))
        (t (error "bad object number"))))

(defun make-frame-loader (synset)
  #'(lambda (plus frame-num which)
      (unless (equal plus "+")
        (error "bad frame marker"))
      (let ((object (get-object (parse-integer which :radix 16)
                                synset))
            (frame (nth (parse-integer frame-num)
                        *verb-sentence-templates*)))
        (if (synset-p object)
            (dolist (sense (synset-senses object))
              (push frame (word-sense-verb-sentence-templates sense)))
          (push frame (word-sense-verb-sentence-templates object))))))

;;;;;;;;;;;;;;;  miscellaneous ;;;;;;;;;;;


(defun pos-index-file (pos)
  (merge-pathnames (str "index." (pos-filename-affix pos))
                   +wordnet-path-default+))
;;;(defun pos-index-file (pos)
;;;  (merge-pathnames (str (pos-filename-affix pos) ".idx")
;;;                   (concatenate 'string *wnsearchdir* "\\")))


(defun pos-data-file (pos)
  (merge-pathnames (str "data." (pos-filename-affix pos))
                   +wordnet-path-default+))
;;;(defun pos-data-file (pos)
;;;  (merge-pathnames (str (pos-filename-affix pos) ".dat" )
;;;                   (concatenate 'string *wnsearchdir* "\\")))


(defun pos-morph-file (pos)
  (merge-pathnames (str (pos-filename-affix pos) ".exc")
                   +wordnet-path-default+))
;;;(defun pos-morph-file (pos)
;;;  (merge-pathnames (str (pos-filename-affix pos) ".exc")
;;;                   (concatenate 'string *wnsearchdir* "\\")))


(defun pos-filename-affix (pos)
  (cdr (assoc pos '((:noun . "noun")
		    (:verb . "verb")
		    (:adjective . "adj")
		    (:adverb . "adv")))))


(defun pos-from-symbol (symbol)
  (cdr (assoc symbol '(("n" . :noun)
		       ("v" . :verb)
		       ("a" . :adjective)
		       ("s" . :adjective) ; satellite
		       ("r" . :adverb))
	      :test #'equal)))


(defun relation-from-symbol (symbol source-type)
  (if (and (eql (char symbol 0)
		#\\)
	   (eq source-type :adverb))
      ;; the only symbol ambiguous with respect to type
      :derived-from-adjective
    (cdr (assoc symbol '(("!" . :antonym)
			 ("@" . :hypernym)
			 ("~" . :hyponym)
			 ("#m" . :meronym-member)
			 ("#s" . :meronym-substance)
			 ("#p" . :meronym-part)
			 ("%m" . :holonym-member)
			 ("%s" . :holonym-substance)
			 ("%p" . :holonym-part)
			 ("=" . :attribute)
			 ("*" . :entailment)
			 (">" . :cause)
			 ("^" . :see-also)
			 ("&" . :similar-to)
			 ("<" . :participle-of-verb)
			 ("\\" . :pertains-to-noun))
		:test #'equal))))

;;;;;;;;;;;;;;; test functions ;;;;;;;;;;;


(defun clear-caches ()
  (clrhash *word-cache*)
  (clrhash *word-sense-cache*)
  (clrhash *synset-cache*))

#|
(setq choke-word (get-word "choke"))
(setq first-choke-sense (first (word-senses choke-word)))
(setq second-choke-sense (second (word-senses choke-word)))
(setq first-choke-synset (word-sense-synset first-choke-sense))
(setq second-choke-synset (word-sense-synset second-choke-sense))
(setq first-choke-data-entry (get-data-entry (synset-file-offset first-choke-synset)
                                             (synset-pos first-choke-synset)))
(setq second-choke-data-entry (get-data-entry (synset-file-offset second-choke-synset)
                                       (synset-pos second-choke-synset)))
(setq first-choke-loader (make-synset-sense-loader first-choke-synset))
(setq second-choke-loader (make-synset-sense-loader second-choke-synset))
(funcall first-choke-loader "choke" "1")
(funcall second-choke-loader "choke" "0")
|#

(defun test1 (word &optional (pos :noun))
  (let ((wd (get-word word pos)))
    (format t "~%The ~A ~A has ~D senses." (word-pos wd) (word-string wd) (word-dict-sense-count wd))
    (loop for i from 1 to (word-dict-sense-count wd)
        for sense in (word-senses wd)
        do (terpri)
          (let ((sentence (synset-gloss (word-sense-synset sense))))
            (setq sentence (subseq sentence 1 (1- (length sentence))))
            (format t "~%~D. ~@(~A.~)" i sentence)))))

(defun synset-hyponyms (synset)
  (loop for pointer in (synset-pointers synset)
      when (eq (pointer-relation pointer) :hyponym)
      collect (pointer-dest pointer)))

(defun synset-hypernyms (synset)
  (loop for pointer in (synset-pointers synset)
      when (eq (pointer-relation pointer) :hypernym)
      collect (pointer-dest pointer)))

(defun test2 (word)
  (let ((wd (get-word word)))
    (format t "~%The ~A ~A has ~D senses." (word-pos wd) (word-string wd) (word-dict-sense-count wd))
    (loop for i from 1 to (word-dict-sense-count wd)
        for sense in (word-senses wd)
        do (terpri)
          (format t "~%Sense ~S" sense)
          (loop for pointer in (print (synset-pointers (print (word-sense-synset sense))))
              when (eq (pointer-relation pointer) :hyponym)
              do (print (mapcar #'(lambda (sense) (word-string (word-sense-word sense)))
                          (print (synset-senses (print (pointer-dest pointer))))))))
    ))

(defun test3 (word)
  (mapcar #'(lambda (sense) (word-sense-synset sense))
    (word-senses (get-word word))))
  
;;; EOF

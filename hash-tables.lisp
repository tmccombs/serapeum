(in-package :serapeum)

(defconstant +hash-table-default-size+
  (hash-table-size (make-hash-table)))

(deftype ok-hash-table-test ()
  '(and (or symbol function)
    (satisfies hash-table-test-p)))

(defun hash-table-test-p (x)
  (etypecase x
    (symbol (member x '(eq eql equal equalp)))
    (function (member x (load-time-value
                         (list #'eq #'eql #'equal #'equalp))))))

(defun copy-hash-table/empty
    (table
     &key (test (hash-table-test table))
          (size (hash-table-size table))
          (rehash-size (hash-table-rehash-size table))
          (rehash-threshold (hash-table-rehash-threshold table)))
  "Make a hash table with the same parameters (test, size, &c.) as
TABLE, but empty."
  (make-hash-table :test test :size size
                   :rehash-size rehash-size
                   :rehash-threshold rehash-threshold))

(defun dict (&rest keys-and-values)
  "A concise constructor for hash tables.

    (gethash :c (dict :a 1 :b 2 :c 3)) => 3, T

By default, return an 'equal hash table containing each successive
pair of keys and values from KEYS-AND-VALUES.

If the number of KEYS-AND-VALUES is odd, then the first argument is
understood as the test.

     (gethash \"string\" (dict \"string\" t)) => t
     (gethash \"string\" (dict 'eq \"string\" t)) => nil"
  (let ((test (if (oddp (length keys-and-values))
                  (pop keys-and-values)
                  'equal)))
    (values (plist-hash-table keys-and-values :test test))))

(define-compiler-macro dict (&rest keys-and-values)
  (let ((test (if (oddp (length keys-and-values))
                  (pop keys-and-values)
                  ''equal)))
    (with-gensyms (ht)
      `(let ((,ht (make-hash-table
                   :test ,test
                   :size ,(max +hash-table-default-size+
                               (truncate (length keys-and-values)
                                         2)))))
         ,@(unsplice
            (when keys-and-values
              `(setf ,@(loop for (key value . nil) on keys-and-values by #'cddr
                             append `((gethash ,key ,ht) ,value)))))
         ,ht))))

(defun dict* (dict &rest args)
  "Merge new bindings into DICT.
Roughly equivalent to `(merge-tables DICT (dict args...))'."
  (doplist (k v args)
    (setf (gethash k dict) v))
  dict)

(defmacro dictq (&rest keys-and-values)
  "A literal hash table.
Like `dict', but the keys and values are implicitly quoted."
  (apply #'dict keys-and-values))

(defun href (table &rest keys)
  "A concise way of doings lookups in (potentially nested) hash tables.

    (href (dict :x 1) :x) => x
    (href (dict :x (dict :y 2)) :x :y)  => y"
  (nlet href ((table table)
              (keys keys))
    (cond ((endp keys) table)
          ((single keys) (gethash (car keys) table))
          (t (href (gethash (car keys) table) (cdr keys))))))

(defun href-default (default table &rest keys)
  "Like `href', with a default.
As soon as one of KEYS fails to match, DEFAULT is returned."
  (nlet href (table keys)
    (cond ((endp keys)
           (values default nil))
          ((single keys)
           (multiple-value-bind (value ok?)
               (gethash (car keys) table)
             (if ok?
                 (values value t)
                 (values default nil))))
          (t (multiple-value-bind (value ok?)
                 (gethash (car keys) table)
               (if ok?
                   (href value (cdr keys))
                   (values default nil)))))))

(defun (setf href) (value table &rest keys)
  (nlet hset ((table table)
              (keys keys))
    (cond ((endp keys) value)
          ((single keys) (setf (gethash (car keys) table) value))
          (t (hset (gethash (car keys) table) (cdr keys))))))

(defun expand-href (table keys)
  (reduce
   (lambda (table key)
     `(gethash ,key ,table))
   keys
   :initial-value table))

(define-compiler-macro href (table &rest keys)
    (expand-href table keys))

(define-compiler-macro (setf href) (value table &rest keys)
  `(setf ,(expand-href table keys) ,value))

(defun @ (table key &rest keys)
  "A concise way of doings lookups in (potentially nested) hash tables.

    (@ (dict :x 1) :x) => x
    (@ (dict :x (dict :y 2)) :x :y)  => y "
    (nlet rec ((table table)
               (keys (cons key keys)))
      (if (single keys)
          (gethash (car keys) table)
          (rec (gethash (car keys) table) (cdr keys)))))

(defun (setf @) (value table key &rest keys)
  (nlet rec ((table table)
             (keys (cons key keys)))
    (if (single keys)
        (setf (gethash (car keys) table) value)
        (rec (gethash (car keys) table) (cdr keys)))))

(flet ((expand-@ (table keys)
         (reduce
          (lambda (table key)
            `(gethash ,key ,table))
          keys
          :initial-value table)))
  (define-compiler-macro @ (table key &rest keys)
      (expand-@ table (cons key keys)))
  (define-compiler-macro (setf @) (value table key &rest keys)
    `(setf ,(expand-@ table (cons key keys)) ,value)))

(defun pophash (key hash-table)
  "Lookup KEY in HASH-TABLE, return its value, and remove it.
From Zetalisp."
  (multiple-value-bind (value present?)
      (gethash key hash-table)
    (when present? (remhash key hash-table))
    (values value present?)))

(defun swaphash (key value hash-table)
  "Set KEY and VALUE in HASH-TABLE, returning the old values of KEY.
From Zetalisp."
  (multiple-value-prog1 (gethash key hash-table)
    (setf (gethash key hash-table) value)))

(declaim (inline hash-fold))
(defun hash-fold (fn init hash-table)
  "Reduce TABLE by calling FN with three values: a key from the hash
table, its value, and the return value of the last call to FN. On the
first call, INIT is supplied in place of the previous value.

From Guile."
  (with-hash-table-iterator (next hash-table)
    (let ((prior init))
      (loop (multiple-value-bind (more k v) (next)
              (if more
                  (setf prior (funcall fn k v prior))
                  (return prior)))))))

(defun maphash-return (fn hash-table)
  "Like MAPHASH, but collect and return the values from FN.
From Zetalisp."
  (let ((fn (ensure-function fn)))
    ;; You were expecting nreverse? Hash tables are unordered.
    (hash-fold (lambda (k v prior)
                 (cons (funcall fn k v) prior))
               '()
               hash-table)))

;; Clojure
(defun merge-tables (table &rest tables)
  "Merge TABLE and TABLES, working from left to right.
The resulting hash table has the same parameters as TABLE.

Clojure's `merge'."
  (let ((size (max +hash-table-default-size+
                   (reduce #'+ tables
                           :key #'hash-table-count
                           :initial-value (hash-table-count table)))))
    (values
     (apply #'merge-tables!
            (copy-hash-table table :size size)
            tables))))

(defun merge-tables! (table &rest tables)
  (reduce (lambda (x y)
            (maphash
             (lambda (k v)
               (setf (gethash k x) v))
             y)
            x)
          tables
          :initial-value table))

(defun flip-hash-table (table &key (test (constantly t)) (key #'identity))
  "Return a table like TABLE, but with keys and values flipped.

     (gethash :y (flip-hash-table (dict :x :y)))
     => :x

TEST filters which keys to set. KEY defaults to `identity'."
  (let ((table2 (copy-hash-table/empty table)))
    (ensuring-functions (key test)
      (maphash (lambda (k v)
                 (let ((key (funcall key k)))
                   (when (funcall test key)
                     (setf (gethash v table2) key))))
               table))
    table2))

(defun set-hash-table (set &rest hash-table-args &key (test #'eql)
                                                      (key #'identity)
                                                      (strict t)
                       &allow-other-keys)
  "Return SET, a list considered as a set, as a hash table.
This is the equivalent of Alexandria's `alist-hash-table' and
`plist-hash-table' for a list that denotes a set.

STRICT determines whether to check that the list actually is a set.

The resulting hash table has the elements of SET for both its keys and
values. That is, each element of SET is stored as if by
     (setf (gethash (key element) table) element)"
  (check-type test ok-hash-table-test)
  (let* ((hash-table-args
           (remove-from-plist hash-table-args
                              :key :strict))
         (table (multiple-value-call #'make-hash-table
                  (values-list hash-table-args)
                  :size (length set))))
    (ensuring-functions (key)
      (if (not strict)
          (dolist (item set)
            (setf (gethash (funcall key item) table) item))
          (dolist (item set)
            (when (nth-value 1 (swaphash (funcall key item) item table))
              (error "Not a set: ~a" set)))))
    table))

(defun hash-table-set (table &key (strict t) (test #'eql) (key #'identity))
  "Return the set denoted by TABLE.
Given STRICT, check that the table actually denotes a set.

Without STRICT, equivalent to `hash-table-values'."
  (let ((set (hash-table-values table)))
    (when strict
      (unless (setp set :test test :key key)
        (error "Not a set: ~a" set)))
    set))

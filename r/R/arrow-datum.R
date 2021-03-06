# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

#' @include arrow-package.R

# Base class for Array, ChunkedArray, and Scalar, for S3 method dispatch only.
# Does not exist in C++ class hierarchy
ArrowDatum <- R6Class("ArrowDatum", inherit = ArrowObject,
  public = list(
    cast = function(target_type, safe = TRUE, ...) {
      opts <- cast_options(safe, ...)
      opts$to_type <- as_type(target_type)
      call_function("cast", self, options = opts)
    }
  )
)

#' @export
length.ArrowDatum <- function(x) x$length()

#' @export
is.na.ArrowDatum <- function(x) call_function("is_null", x)

#' @export
is.nan.ArrowDatum <- function(x) call_function("is_nan", x)

#' @export
as.vector.ArrowDatum <- function(x, mode) x$as_vector()

filter_rows <- function(x, i, keep_na = TRUE, ...) {
  # General purpose function for [ row subsetting with R semantics
  # Based on the input for `i`, calls x$Filter, x$Slice, or x$Take
  nrows <- x$num_rows %||% x$length() # Depends on whether Array or Table-like
  if (inherits(i, "array_expression")) {
    # Evaluate it
    i <- eval_array_expression(i)
  }
  if (is.logical(i)) {
    if (isTRUE(i)) {
      # Shortcut without doing any work
      x
    } else {
      i <- rep_len(i, nrows) # For R recycling behavior; consider vctrs::vec_recycle()
      x$Filter(i, keep_na)
    }
  } else if (is.numeric(i)) {
    if (all(i < 0)) {
      # in R, negative i means "everything but i"
      i <- setdiff(seq_len(nrows), -1 * i)
    }
    if (is.sliceable(i)) {
      x$Slice(i[1] - 1, length(i))
    } else if (all(i > 0)) {
      x$Take(i - 1)
    } else {
      stop("Cannot mix positive and negative indices", call. = FALSE)
    }
  } else if (is.Array(i, INTEGER_TYPES)) {
    # NOTE: this doesn't do the - 1 offset
    x$Take(i)
  } else if (is.Array(i, "bool")) {
    x$Filter(i, keep_na)
  } else {
    # Unsupported cases
    if (is.Array(i)) {
      stop("Cannot extract rows with an Array of type ", i$type$ToString(), call. = FALSE)
    }
    stop("Cannot extract rows with an object of class ", class(i), call.=FALSE)
  }
}

#' @export
`[.ArrowDatum` <- filter_rows

#' @importFrom utils head
#' @export
head.ArrowDatum <- function(x, n = 6L, ...) {
  assert_is(n, c("numeric", "integer"))
  assert_that(length(n) == 1)
  len <- NROW(x)
  if (n < 0) {
    # head(x, negative) means all but the last n rows
    n <- max(len + n, 0)
  } else {
    n <- min(len, n)
  }
  if (n == len) {
    return(x)
  }
  x$Slice(0, n)
}

#' @importFrom utils tail
#' @export
tail.ArrowDatum <- function(x, n = 6L, ...) {
  assert_is(n, c("numeric", "integer"))
  assert_that(length(n) == 1)
  len <- NROW(x)
  if (n < 0) {
    # tail(x, negative) means all but the first n rows
    n <- min(-n, len)
  } else {
    n <- max(len - n, 0)
  }
  if (n == 0) {
    return(x)
  }
  x$Slice(n)
}

is.sliceable <- function(i) {
  # Determine whether `i` can be expressed as a $Slice() command
  is.numeric(i) &&
    length(i) > 0 &&
    all(i > 0) &&
    identical(as.integer(i), i[1]:i[length(i)])
}

#' @export
as.double.ArrowDatum <- function(x, ...) as.double(as.vector(x), ...)

#' @export
as.integer.ArrowDatum <- function(x, ...) as.integer(as.vector(x), ...)

#' @export
as.character.ArrowDatum <- function(x, ...) as.character(as.vector(x), ...)

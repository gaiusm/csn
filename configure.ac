dnl Process this file with autoconf to produce a configure script.

AC_INIT([libcsn], [2.0], [gaiusmod2@gmail.com])
AC_PREREQ(2.69)

AM_INIT_AUTOMAKE([-Wall -Werror foreign -Wno-portability])

AC_PROG_CC
AM_PROG_AR

LT_INIT
LT_PREREQ([])
AC_SUBST([LIBTOOL_DEPS])

AC_CONFIG_SRCDIR([version.c])
AC_CONFIG_MACRO_DIR([m4])

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([
 Makefile
 src/Makefile
 mrun/mrun mrun/csnconfig.py
])
AC_OUTPUT

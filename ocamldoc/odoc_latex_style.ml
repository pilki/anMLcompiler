(***********************************************************************)
(*                             OCamldoc                                *)
(*                                                                     *)
(*            Maxence Guesdon, projet Cristal, INRIA Rocquencourt      *)
(*                                                                     *)
(*  Copyright 2001 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(** The content of the LaTeX style to generate when generating LaTeX code. *)

(* $Id$ *)

let content ="
%% Support macros for LaTeX documentation generated by ocamldoc.
%% This file is in the public domain; do what you want with it.

\\NeedsTeXFormat{LaTeX2e}
\\ProvidesPackage{ocamldoc}
              [2001/12/04 v1.0 ocamldoc support]

\\newenvironment{ocamldoccode}{%
  \\bgroup
  \\leftskip\\@totalleftmargin
  \\rightskip\\z@skip
  \\parindent\\z@
  \\parfillskip\\@flushglue
  \\parskip\\z@skip 
  %\\noindent
  \\@@par\\smallskip
  \\@tempswafalse
  \\def\\par{%
    \\if@tempswa
      \\leavevmode\\null\\@@par\\penalty\\interlinepenalty
  \\else
    \\@tempswatrue
    \\ifhmode\\@@par\\penalty\\interlinepenalty\\fi
  \\fi}
  \\obeylines
  \\verbatim@font
  \\let\\org@prime~%
  \\@noligs
  \\let\\org@dospecials\\dospecials
  \\g@remfrom@specials{\\\\}
  \\g@remfrom@specials{\\{}
  \\g@remfrom@specials{\\}}
  \\let\\do\\@makeother
  \\dospecials
  \\let\\dospecials\\org@dospecials
  \\frenchspacing\\@vobeyspaces
  \\everypar \\expandafter{\\the\\everypar \\unpenalty}}
{\\egroup\\par}

\\def\\g@remfrom@specials#1{%
  \\def\\@new@specials{}
  \\def\\@remove##1{%
    \\ifx##1#1\\else
    \\g@addto@macro\\@new@specials{\\do ##1}\\fi}
  \\let\\do\\@remove\\dospecials
  \\let\\dospecials\\@new@specials
  }

\\newenvironment{ocamldocdescription}
{\\list{}{\\rightmargin0pt \\topsep0pt}\\raggedright\\item\\noindent\\relax\\ignorespaces}
{\\endlist\\medskip}

\\newenvironment{ocamldoccomment}
{\\list{}{\\leftmargin 2\\leftmargini \\rightmargin0pt \\topsep0pt}\\raggedright\\item\\noindent\\relax}
{\\endlist}

\\let \\ocamldocparagraph \\paragraph
\\def \\paragraph #1{\\ocamldocparagraph {#1}\\noindent}
\\let \\ocamldocsubparagraph \\subparagraph
\\def \\subparagraph #1{\\ocamldocsubparagraph {#1}\\noindent}

\\let\\ocamldocvspace\\vspace

\\newenvironment{ocamldocindent}{\\list{}{}\\item\\relax}{\\endlist}
\\newenvironment{ocamldocsigend}
     {\\noindent\\quad\\texttt{sig}\\ocamldocindent}
     {\\endocamldocindent\\vskip -\\lastskip
      \\noindent\\quad\\texttt{end}\\medskip}
\\newenvironment{ocamldocobjectend}
     {\\noindent\\quad\\texttt{object}\\ocamldocindent}
     {\\endocamldocindent\\vskip -\\lastskip
      \\noindent\\quad\\texttt{end}\\medskip}

\\endinput
"


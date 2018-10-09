MODULE Def;  (** CAS 10 Jul 92 / TK 8.10.2018 for RISC **)
  IMPORT
    Viewers, Fonts, Texts, MenuViewers, TextFrames, Oberon;

  CONST
    Menu = "System.Close System.Copy System.Grow Edit.Search Edit.Store";
    TAB = 9X;  CR = 0DX;  MaxMod = 32;
    module = 0;  import = 1;  const = 2;  type = 3;  class = 4;  var = 5;  procedure = 6;  begin = 7;  end = 8;
    period = 9;  array = 10;  record = 11;  of = 12;  pointer = 13;  to = 14;  asterisk = 15;  comma = 16;  colon = 17;
    equal = 18;  lparen = 19;  rparen = 20;  semicolon = 21;  arrow = 22;  slash = 23;  minus = 24;  ident = 25;
    endident = 29;  endmod = 30;  eot = 31;  none = 99;

  VAR
    B: Texts.Buffer;
    TMod: Texts.Text;
    plainFont: Fonts.Font;
    W, WL: Texts.Writer;
    R: Texts.Reader;

    wpos, pos, cpos: LONGINT;
    mods: INTEGER;  (*no of "exported" modules*)
    mod: ARRAY MaxMod OF RECORD
      exp, break: BOOLEAN;
      beg, end: LONGINT;
      name: ARRAY 32 OF CHAR
    END;

    sym, tag, line, level, nlines: INTEGER;
    newline, plain: BOOLEAN;
    ch: CHAR;
    id: ARRAY (*64*) 32 OF CHAR;

    comment: RECORD
      exp, break, split: BOOLEAN;
      wpos, pos0, pos1: LONGINT
    END;

	(* forward reference *)
    constructor: PROCEDURE;


  PROCEDURE AppendDef(VAR s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    s[i] := "."; s[i+1] := "D"; s[i+2] := "e"; s[i+3] := "f"; s[i+4] := 0X
  END AppendDef;

  PROCEDURE DefSuffix(VAR s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE s[i] # 0X DO
      IF (s[i] = ".") & (s[i+1] = "M") & (s[i+2] = "o") & (s[i+3] = "d") & (s[i+4] = 0X) THEN
        s[i] := 0X; AppendDef(s)
      END;
      INC(i)
    END
  END DefSuffix;


  PROCEDURE Mark(err: INTEGER);
  BEGIN Texts.WriteString(WL, "  pos   "); Texts.WriteInt(WL, pos, 0);
    IF err = 0 THEN Texts.WriteString(WL, "  not a module")
    ELSIF err = 2 THEN Texts.WriteString(WL, "  end of module missing")
    END;
    Texts.WriteLn(WL); Texts.Append(Oberon.Log, WL.buf)
  END Mark;

  PROCEDURE Pos(): LONGINT;
  BEGIN RETURN Texts.Pos(R)-1
  END Pos;

  PROCEDURE PickAttr(attr: LONGINT);
    VAR R: Texts.Reader; ch: CHAR;
  BEGIN Texts.OpenReader(R, TMod, attr); Texts.Read(R, ch);
    Texts.SetFont(W, R.fnt); Texts.SetColor(W, R.col); Texts.SetOffset(W, R.voff)
  END PickAttr;

  PROCEDURE Wr(attr: LONGINT; ch: CHAR);
  BEGIN PickAttr(attr); Texts.Write(W, ch)
  END Wr;

  PROCEDURE WrS(attr: LONGINT; s: ARRAY OF CHAR);
  BEGIN PickAttr(attr); Texts.WriteString(W, s)
  END WrS;

  PROCEDURE WrLn;
  BEGIN Texts.WriteLn(W)
  END WrLn;

  PROCEDURE Indent(n: INTEGER);
  BEGIN WrLn; Texts.SetFont(W, plainFont);
    WHILE n > 0 DO Texts.Write(W, TAB); DEC(n) END
  END Indent;

  PROCEDURE Break(break: BOOLEAN; n: INTEGER);
  BEGIN
    IF break THEN Indent(n) ELSE Texts.SetFont(W, plainFont); Texts.Write(W, " ") END
  END Break;

  PROCEDURE Append(SB, DB: Texts.Buffer);
  BEGIN Texts.Copy(SB, DB); Texts.OpenBuf(SB)
  END Append;

  PROCEDURE InsertBuf(B: Texts.Buffer; text: Texts.Text; VAR pos: LONGINT);
    VAR len: LONGINT;
  BEGIN len := B.len; Texts.Insert(text, pos, B); INC(pos, len)
  END InsertBuf;

  PROCEDURE Insert(beg, end: LONGINT; text: Texts.Text; VAR pos: LONGINT);
    VAR buf: Texts.Buffer;
  BEGIN NEW(buf); Texts.OpenBuf(buf); Texts.Save(TMod, beg, end, buf);
    InsertBuf(W.buf, text, pos); InsertBuf(buf, text, pos)
  END Insert;

  PROCEDURE Disp(beg, end: LONGINT);
  BEGIN Append(W.buf, B); Texts.Save(TMod, beg, end, B)
  END Disp;


  (* scanner *)

  PROCEDURE CAP(ch: CHAR): CHAR;
    VAR up: CHAR;
  BEGIN
    IF (ch >= "a") & (ch <= "z") THEN
      up := CHR(ORD(ch) + ORD("A") - ORD("a"))
    ELSE up := ch END
  RETURN up END CAP;

  PROCEDURE Ch;
  BEGIN
    IF ch = CR THEN INC(line) END;
    Texts.Read(R, ch)
  END Ch;

  PROCEDURE Comment;
    VAR ch0: CHAR;  lev, cnt: INTEGER;  pos1: LONGINT;
  BEGIN ch0 := ch; lev := 1; cnt := 0;
    (*IF ch = "*" THEN Ch;
      IF ch = ")" THEN Ch; RETURN END
    END;*)
    REPEAT
      IF ch = "*" THEN Ch; INC(cnt);
        IF ch = ")" THEN Ch; DEC(lev) END
      ELSIF ch = "(" THEN Ch; cnt := 0;
        IF ch = "*" THEN Ch; INC(lev) END
      ELSE Ch; cnt := 0
      END
    UNTIL (lev = 0) OR R.eot;
    IF ch0 = "*" THEN comment.exp := TRUE;  (*exported comment*)
      comment.break := nlines >= 2; comment.wpos := wpos; comment.pos0 := pos;
      pos1 := Pos(); comment.pos1 := pos1; comment.split := (cnt > 1) & (pos+5 < pos1)
    ELSE comment.exp := FALSE
    END
  END Comment;

  PROCEDURE FlushComment;
  BEGIN
    IF comment.exp THEN
      IF comment.break THEN WrLn END;
      Disp(comment.wpos, comment.pos0); Disp(comment.pos0, comment.pos0 + 1);
      IF comment.split THEN Disp(comment.pos0 + 2, comment.pos1 - 2); Disp(comment.pos1 - 1, comment.pos1)
      ELSE Disp(comment.pos0 + 2, comment.pos1)
      END;
      comment.exp := FALSE
    END
  END FlushComment;

  PROCEDURE Ident;
    VAR i: INTEGER;
  BEGIN sym := ident; i := 0;
    REPEAT id[i] := ch; Ch; INC(i) UNTIL (ch < "0") OR (ch > "9") & (CAP(ch) < "A") OR (CAP(ch) > "Z");
    id[i] := 0X
  END Ident;

  PROCEDURE Sym;
    VAR ch0: CHAR; ln: INTEGER;
  BEGIN
    IF sym # eot THEN (*RETURN END;*)
      sym := none; ln := line;
      WHILE ~R.eot & (sym = none) DO
        wpos := Pos();
        WHILE ~R.eot & (ch <= " ") DO
          IF ch = 0DX THEN wpos := Pos() END;
          Ch
        END;
        pos := Pos(); nlines := line - ln; newline := nlines # 0;
        IF (ch >= "a") & (ch <= "z") THEN ch0 := CAP(ch) ELSE ch0 := ch END;
        IF (ch0 >= "A") & (ch0 <= "Z") THEN Ident ELSE Ch END;
        (*CASE ch0 OF
          0X.."!", "#".."'", "+", "0".."9", "<", ">".."@":*)
        IF (ch0 >= 0X) & (ch0 <= "!") OR (ch0 >= "#") & (ch0 <= "'") OR (ch0 = "+")  OR
            (ch0 >= "0") & (ch0 <= "9") OR (ch0 = "<") & (ch0 >= ">") & (ch0 <= "@") THEN (*skip*)
        ELSIF ch0 = 22X THEN REPEAT Ch UNTIL (ch = 22X) OR (ch < " ") OR R.eot; Ch (*string*)
        ELSIF ch0 = "(" THEN IF ch = "*" THEN Ch; Comment; FlushComment ELSE sym := lparen END
        ELSIF ch0 = ")" THEN sym := rparen
        ELSIF ch0 = "*" THEN sym := asterisk
        ELSIF ch0 = "," THEN sym := comma
        ELSIF ch0 = "-" THEN sym := minus
        ELSIF ch0 = "." THEN IF ch # "." THEN sym := period END
        ELSIF ch0 = "/" THEN sym := slash
        ELSIF ch0 = ":" THEN sym := colon
        ELSIF ch0 = ";" THEN sym := semicolon
        ELSIF ch0 = "=" THEN sym := equal
        (*"D", "F".."H", "J".."L", "N", "Q", "S", "U", "W".."Z":*)
        ELSIF (ch0 = "D") OR (ch0 >= "F") & (ch0 <= "H") OR (ch0 >= "J") & (ch0 <= "J") OR (ch0 = "N") OR
                  (ch0 = "Q") OR (ch0 = "S") OR (ch0 = "U") OR (ch0 >= "W") & (ch0 <= "Z") THEN (*skip*)
        ELSIF ch0 = "A" THEN IF id = "ARRAY" THEN sym := array END
        ELSIF ch0 = "B" THEN IF id = "BEGIN" THEN sym := begin END
        ELSIF ch0 = "C" THEN IF id = "CONST" THEN sym := const ELSIF id = "CLASS" THEN sym := class END
        ELSIF ch0 = "E" THEN IF id = "END" THEN sym := end END
        ELSIF ch0 = "I" THEN IF id = "IMPORT" THEN sym := import END
        ELSIF ch0 = "M" THEN IF id = "MODULE" THEN sym := module END
        ELSIF ch0 = "O" THEN IF id = "OF" THEN sym := of END
        ELSIF ch0 = "P" THEN IF id = "PROCEDURE" THEN sym := procedure ELSIF id = "POINTER" THEN sym := pointer END
        ELSIF ch0 = "R" THEN IF id = "RECORD" THEN sym := record END
        ELSIF ch0 = "T" THEN IF id = "TYPE" THEN sym := type ELSIF id = "TO" THEN sym := to END
        ELSIF ch0 = "V" THEN IF id = "VAR" THEN sym := var END
        (*"[", "\", "]":*)
        ELSIF (ch0 = "[") OR (ch0 = "\") OR (ch0 = "]") THEN (*skip*)
        ELSIF ch0 = "^" THEN sym := arrow
        ELSIF ch0 = "|" THEN sym := semicolon  (*nearly - but does the job*)
        (*"_".."{", "}"..0FFX:*)
        ELSIF (ch0 >= "-") & (ch0 <= "{") OR (ch0 >= "}") & (ch0 <= 0FFX) THEN (*skip*)
        END
      END;
      IF R.eot THEN sym := eot END
    END
  END Sym;

  PROCEDURE Seek(syms: SET; exporting: BOOLEAN);
    VAR first, emod, return: BOOLEAN;  m: INTEGER;
  BEGIN return := FALSE;
    IF sym # endmod THEN syms := syms + {endmod, eot}; emod := ~(end IN syms);
      REPEAT first := sym # period;
        IF exporting & first & (sym = ident) THEN m := 0;
          WHILE m < mods DO
            IF id = mod[m].name THEN mod[m].exp := TRUE END;
            INC(m)
          END;
          first := FALSE;
          IF ident IN syms THEN return := TRUE (*RETURN*) END;
          Sym
        ELSIF emod & (sym = end) THEN cpos := pos; Sym;
          IF sym = ident THEN Sym;
            IF (sym = period) OR (sym = eot) THEN sym := endmod
            ELSIF sym = semicolon THEN sym := endident
            END
          END
        ELSE Sym
        END
      UNTIL (sym IN syms) OR return (*ident IN syms*)
    END
  END Seek;


  (* projector *)

  PROCEDURE ShowType(show: BOOLEAN; newlev: INTEGER);
    VAR exp, first, break, skip, limited: BOOLEAN;  pos1, pos2: LONGINT;  oldlev: INTEGER;
  BEGIN Seek({ident, record, array, pointer, procedure}, show); oldlev := level; level := newlev;
    IF sym = record THEN pos1 := pos; pos2 := Pos(); Seek({lparen, ident, end}, show); exp := FALSE;
      IF sym = lparen THEN Seek({rparen}, show); pos2 := Pos(); Seek({ident, end}, show) END;
      IF show THEN Disp(pos1, pos2) END;
      WHILE sym = ident DO first := TRUE; skip := FALSE;
        REPEAT pos1 := pos; pos2 := Pos(); break := newline; Seek({asterisk, minus, comma, colon}, show);
          IF sym IN {asterisk, minus} THEN limited := sym = minus; Seek({comma, colon}, show);
            IF show THEN
              IF first THEN
                IF exp THEN Wr(pos, ";") END;
                Break(break OR skip, level+1); skip := FALSE
              ELSE WrS(pos, ", ")
              END;
              IF limited THEN Disp(pos1, pos) ELSE Disp(pos1, pos2) END;
              exp := TRUE; first := FALSE
            END
          ELSE skip := TRUE
          END;
          IF sym = comma THEN Seek({ident}, show) END
        UNTIL sym IN {colon, eot};
        IF sym = colon THEN
          IF exp & ~first THEN WrS(pos, ": ") END;
          ShowType(exp & ~first, level+1)
        END;
        IF sym # end THEN Seek({ident, end}, show) END
      END;
      IF show & (sym = end) THEN
        IF ~exp THEN Wr(Pos(), " ") ELSE Indent(level) END;
        Disp(pos, Pos())
      END
    ELSIF sym = array THEN pos1 := pos; Seek({of}, show);
      IF show THEN Disp(pos1, Pos()); Wr(Pos(), " ") END;
      ShowType(show, level)
    ELSIF sym = pointer THEN pos1 := pos; Seek({to}, show);
      IF show THEN Disp(pos1, Pos()); Wr(Pos(), " ") END;
      ShowType(show, level)
    ELSIF sym = procedure THEN pos1 := pos; pos2 := Pos(); Seek({lparen, semicolon, end}, show);
      IF sym = lparen THEN Seek({rparen}, show); Seek({semicolon, end}, show); pos2 := pos END;
      IF show THEN Disp(pos1, pos2) END
    ELSE (*simple type*) pos1 := pos; pos2 := Pos(); Seek({period, semicolon, end}, show);
      WHILE sym = period DO Seek({ident}, FALSE); pos2 := Pos(); Seek({period, semicolon, end}, FALSE) END;
      IF show THEN Disp(pos1, pos2) END
    END;
    level := oldlev
  END ShowType;


  PROCEDURE Import(VAR ins, beg, end: LONGINT);
  BEGIN Append(W.buf, B); ins := B.len; beg := pos; end := Pos(); level := 1;
    REPEAT Seek({ident, const, type, class, var, procedure}, FALSE);
      IF sym = ident THEN mod[mods].beg := pos; (*COPY(id, mod[mods].name);*) mod[mods].name := id;
        mod[mods].break := newline; Seek({semicolon, comma, asterisk}, FALSE);
        mod[mods].end := pos; mod[mods].exp := FALSE;
        IF sym = asterisk THEN Seek({semicolon, comma}, FALSE) END;
        INC(mods)
      END
    UNTIL sym IN {const, type, class, var, procedure, endmod, eot};
    level := 0
  END Import;

  PROCEDURE GenImports(text: Texts.Text; ins, beg, end: LONGINT);
    VAR m: INTEGER;  exp: BOOLEAN;
  BEGIN m := 0; exp := FALSE; pos := ins;
    WHILE m < mods DO
      IF mod[m].exp THEN
        IF exp THEN Wr(mod[m].end, ",")
        ELSE Indent(1); Insert(beg, end, text, pos);
          IF ~mod[m].break THEN Break(mod[0].break, 2) END
        END;
        exp := TRUE; Break(mod[m].break, 2); Insert(mod[m].beg, mod[m].end, text, pos)
      END;
      INC(m)
    END;
    IF exp THEN Wr(pos, ";"); InsertBuf(W.buf, text, pos) END
  END GenImports;


  (*PROCEDURE^ Constructor;*)

  PROCEDURE Const;
    VAR pos0, pos1, pos2: LONGINT;  break, exp: BOOLEAN;
  BEGIN pos0 := pos; pos1 := Pos(); exp := FALSE;
    Seek({ident, const, type, class, var, procedure}, FALSE);
    INC(level);
    WHILE sym = ident DO pos2 := pos; break := newline; Seek({equal, asterisk}, FALSE);
      IF sym = asterisk THEN
        IF ~exp & (tag # const) THEN WrLn; Indent(level); Disp(pos0, pos1) END;
        Break(break, level + 1); Disp(pos2, pos); pos2 := Pos();
        Seek({semicolon}, TRUE); Disp(pos2, Pos()); exp := TRUE; tag := const
      ELSE Seek({semicolon}, TRUE)
      END;
      Seek({ident, const, type, class, var, procedure, begin, endident}, FALSE)
    END;
    DEC(level)
  END Const;

  PROCEDURE Type;
    VAR pos0, pos1, pos2: LONGINT;  first, break, exp: BOOLEAN;
  BEGIN pos0 := pos; pos1 := Pos(); exp := FALSE;
    Seek({ident, const, type, class, var, procedure}, FALSE);
    INC(level);
    WHILE sym = ident DO first := TRUE; pos2 := pos; break := newline; Seek({equal, asterisk}, FALSE);
      IF sym = asterisk THEN
        IF ~exp & (tag # type) THEN WrLn; Indent(level); Disp(pos0, pos1) END;
        Break(break, level + 1); Disp(pos2, pos); pos2 := Pos();
        Seek({equal}, FALSE); Disp(pos2, Pos());
        Wr(Pos(), " "); ShowType(TRUE, level + 1); first := FALSE; exp := TRUE; tag := type
      ELSIF sym = equal THEN ShowType(FALSE, level + 1)
      END;
      IF ~first THEN Wr(Pos(), ";") END;
      Seek({ident, const, type, class, var, procedure, begin, endident}, FALSE)
    END;
    DEC(level)
  END Type;

  PROCEDURE Var(instance: BOOLEAN);
    VAR pos0, pos1, pos2: LONGINT;  first, skip, break, exp, limited: BOOLEAN;
  BEGIN pos0 := pos; pos1 := Pos(); exp := FALSE;
    Seek({ident, const, type, class, var, procedure, endident}, FALSE);
    INC(level);
    WHILE sym = ident DO first := TRUE; break := newline OR instance; skip := FALSE;
      WHILE sym = ident DO pos2 := pos; Seek({colon, comma, asterisk, minus}, FALSE);
        IF sym IN {asterisk, minus} THEN limited := sym = minus;
          IF ~exp & (tag # var) & ~instance THEN WrLn; Indent(level); Disp(pos0, pos1) END;
          IF first THEN Break(break OR skip, level + 1) ELSE WrS(Pos(), ", ") END;
          IF limited THEN Disp(pos2, Pos()) ELSE Disp(pos2, pos) END;
          Seek({colon, comma}, FALSE); first := FALSE; exp := TRUE; skip := FALSE; tag := var
        ELSE skip := TRUE
        END;
        IF sym = comma THEN Seek({ident}, FALSE); break := newline
        ELSIF sym = colon THEN
          IF ~first THEN WrS(Pos(), ": ") END;
          ShowType(~first, level + 1)
        END
      END;
      IF ~first THEN Wr(Pos(), ";") END;
      Seek({ident, const, type, class, var, procedure, begin, endident}, FALSE)
    END;
    DEC(level)
  END Var;

  PROCEDURE Procedure;
    VAR pos0, pos1: LONGINT;  savetag: INTEGER;
  BEGIN pos0 := pos; Seek({arrow, asterisk, slash, ident, lparen}, FALSE);
    IF sym IN {asterisk, slash} THEN Seek({ident, lparen}, FALSE) END;
    IF sym = lparen THEN Seek({rparen}, FALSE); Seek({ident}, FALSE) END;
    IF sym = ident THEN pos1 := Pos(); Seek({lparen, semicolon, asterisk}, FALSE);
      IF sym = asterisk THEN
        IF tag # procedure THEN WrLn END;
        INC(level); Indent(level); Disp(pos0, pos1); pos0 := Pos(); Seek({lparen, semicolon}, FALSE);
        IF sym = lparen THEN Seek({rparen}, TRUE); Seek({semicolon}, TRUE) END;
        Disp(pos0, Pos()); tag := procedure; DEC(level)
      ELSIF sym = lparen THEN Seek({rparen}, FALSE)
      END
    ELSE Seek({lparen, semicolon}, FALSE);
      IF sym = lparen THEN Seek({rparen}, FALSE) END
    END;
    Seek({const, type, class, var, procedure, endident}, FALSE); savetag := tag;
    WHILE sym IN {const, type, class, var, procedure} DO constructor END;
    Seek({const, type, class, var, procedure, endident}, FALSE); tag := savetag
  END Procedure;

  PROCEDURE Class;
    VAR pos0: LONGINT; forward: BOOLEAN;
  BEGIN pos0 := pos; Seek({arrow, asterisk, semicolon}, FALSE); forward := sym = arrow;
    IF forward THEN Seek({asterisk, semicolon}, FALSE) END;
    IF sym = asterisk THEN WrLn; Indent(level + 1); Disp(pos0, pos);
      Seek({lparen, semicolon}, FALSE);
      IF sym = lparen THEN pos0 := pos; Seek({rparen}, TRUE); Disp(pos0, Pos()); Seek({semicolon}, FALSE) END;
      tag := procedure;
      Disp(pos, Pos()); REPEAT Var(TRUE) UNTIL sym # ident;
      IF forward & (sym # endident) THEN Seek({endident}, FALSE)
      ELSE INC(level);
        WHILE sym = procedure DO Procedure END;
        DEC(level)
      END;
      Indent(level + 1); Disp(cpos, Pos()); tag := class
    ELSE (*sym = semicolon*)
      REPEAT Var(TRUE) UNTIL sym # ident;
      IF forward & (sym # endident) THEN Seek({endident}, FALSE)
      ELSE
        WHILE sym = procedure DO Procedure END
      END
    END;
    Seek({const, type, class, var, procedure, endident}, FALSE)
  END Class;

  (*PROCEDURE Constructor;
  BEGIN
    CASE sym OF
      const: Const | type: Type | class: Class | var: Var(FALSE) | procedure: Procedure
    END;
    IF sym = begin THEN Seek({const, type, class, var, procedure, endident}, FALSE) END
  END Constructor;*)

  PROCEDURE Constructor;
  BEGIN
    IF sym = const THEN Const
    ELSIF sym = type THEN Type
    ELSIF sym = class THEN Class
    ELSIF sym = var THEN Var(FALSE)
    ELSIF sym = procedure THEN Procedure
    END;
    IF sym = begin THEN Seek({const, type, class, var, procedure, endident}, FALSE) END
  END Constructor;


  PROCEDURE Show*;  (** ( "*" | "^" | name ) [ "/P" ]   --P option enforces plain text style **)
    VAR S: Texts.Scanner;  V: Viewers.Viewer;  text: Texts.Text;  name: ARRAY 32 OF CHAR;
      selbeg, selend, time: LONGINT;  x, y: INTEGER;
      defpos, modbeg, modend, impins, impbeg, impend: LONGINT;

  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Char) & (S.c = "*") & (S.line = 0) THEN V := Oberon.MarkedViewer();
      IF (V # NIL) & (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
        TMod := V.dsc.next(TextFrames.Frame).text; S.s[0] := "*"; S.s[1] := 0X
      ELSE (*RETURN*)
      END
    ELSIF (S.class = Texts.Name) & (S.line = 0) THEN TMod := TextFrames.Text(S.s)
    ELSE Oberon.GetSelection(text, selbeg, selend, time);
      IF time > 0 THEN Texts.OpenScanner(S, text, selbeg); Texts.Scan(S);
        IF (S.class # Texts.Name) OR (S.line > 0) THEN (*RETURN*) END
      ELSE (*RETURN*)
      END;
      TMod := TextFrames.Text(S.s)
    END;
    (*COPY(S.s, name);*) name := S.s; DefSuffix(name); Texts.Scan(S);
    plain := FALSE; IF (S.class = Texts.Char) & (S.c = "/") THEN plain := CAP(S.nextCh) = "P" END;
    Texts.OpenBuf(W.buf); Texts.OpenBuf(WL.buf); Texts.OpenBuf(B);
    Texts.OpenReader(R, TMod, 0); ch := 0X; Ch; sym := none; line := 0; level := 0; Sym;

    IF sym = module THEN defpos := pos; WrS(defpos, "DEFINITION "); Seek({ident}, FALSE);
      IF name[0] = "*" THEN (*COPY(id, name);*) name := id; AppendDef(name) END;
      modbeg := pos; modend := Pos(); Seek({semicolon}, FALSE);
      Disp(modbeg, modend); Disp(pos, Pos()); Seek({import, const, type, class, var, procedure}, FALSE);
      mods := 0; tag := none;
      IF sym = import THEN Import(impins, impbeg, impend) END;
      WHILE sym IN {const, type, class, var, procedure} DO Constructor END;
      IF sym # endmod THEN Seek({}, FALSE) END;
      IF sym = endmod THEN WrLn; Disp(cpos, Pos());
        WHILE sym # eot DO Sym END;
        text := TextFrames.Text(""); WrLn; Append(W.buf, B); Texts.Append(text, B);
        GenImports(text, impins, impbeg, impend);
        IF plain THEN Texts.ChangeLooks(text, 0, text.len, {0}, plainFont, 0, 0) END;
        Oberon.AllocateUserViewer((*Oberon.Mouse.X*) 0, x, y);
        V := MenuViewers.New(TextFrames.NewMenu(name, Menu), TextFrames.NewText(text, 0),
          TextFrames.menuH, x, y)
      ELSE Mark(2)
      END;
      TMod := NIL
    ELSE Mark(0)
    END
  END Show;

BEGIN Texts.OpenWriter(W); Texts.OpenWriter(WL); NEW(B); plainFont := Fonts.This("Oberon10.Scn.Fnt");
  constructor := Constructor
END Def.


Def.Show ^
Def.Show *
Def.Show ~

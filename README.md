# DEFINITION module

This is a port of `Def.Mod' from Oberon-V4 to Oberon-V5 system. It's only command *Show* outputs definition of a given module, i.e. it collects any procedures, data types or variables flagged by asterisk for export in the text. It reflects Oberon-2, Oberon-7 syntax. The *Def.Mod* combines the function of a scanner, and the parser.

*Exported comments* are recognised and included in the definition, ading documentation.

**Exported comment**

	(** this is an exported comment **)

**Command toolbox**

	Def.Show ^
	Def.Show *
	Def.Show ~

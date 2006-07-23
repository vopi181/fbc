''	FreeBASIC - 32-bit BASIC Compiler.
''	Copyright (C) 2004-2006 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
''
''	This program is free software; you can redistribute it and/or modify
''	it under the terms of the GNU General Public License as published by
''	the Free Software Foundation; either version 2 of the License, or
''	(at your option) any later version.
''
''	This program is distributed in the hope that it will be useful,
''	but WITHOUT ANY WARRANTY; without even the implied warranty of
''	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''	GNU General Public License for more details.
''
''	You should have received a copy of the GNU General Public License
''	along with this program; if not, write to the Free Software
''	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.


'' NAMESPACE..END NAMESPACE compound statement parsing
''
'' chng: may/2006 written [v1ctor]

option explicit
option escape

#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\parser.bi"
#include once "inc\ast.bi"

'':::::
''NamespaceStmtBegin  =   NAMESPACE (ID (ALIAS LITSTR)?)? .
''
function cNamespaceStmtBegin _
	( _
		_
	) as integer

    static as zstring * FB_MAXNAMELEN+1 id, id_alias
    dim as zstring ptr palias = any
    dim as FBSYMBOL ptr sym = any
    dim as FBSYMCHAIN ptr chain_ = any
    dim as FB_CMPSTMTSTK ptr stk = any
    dim as integer levels = any

	function = FALSE

    if( cCompStmtIsAllowed( FB_CMPSTMT_MASK_NAMESPC ) = FALSE ) then
    	'' error recovery: skip the whole compound stmt
    	hSkipCompound( FB_TK_NAMESPACE )
    	exit function
    end if

	'' skip NAMESPACE, don't lookup '.'s
	lexSkipToken( LEXCHECK_NOLOOKUP )

	'' ID?
	palias = NULL

	select case lexGetToken( )
	'' COMMENT|NEWLINE?
	case FB_TK_COMMENTCHAR, FB_TK_REM, FB_TK_EOL, FB_TK_EOF, FB_TK_STATSEPCHAR

		'' anonymous namespace..
		sym = symbAddNamespace( hMakeTmpStr( ), NULL )

		stk = cCompStmtPush( FB_TK_NAMESPACE, _
					 	 	 FB_CMPSTMT_MASK_ALL and (not FB_CMPSTMT_MASK_CODE) _
					 					 	 	 and (not FB_CMPSTMT_MASK_EXTERN) _
					 					 	 	 and (not FB_CMPSTMT_MASK_DATA) )

		stk->nspc.node = astNamespaceBegin( sym )
		stk->nspc.levels = 1

		return TRUE
	end select

    levels = 0
    do
        levels += 1

    	'' not an id?
    	if( lexGetToken( ) <> FB_TK_ID ) then
			if( errReport( FB_ERRMSG_EXPECTEDIDENTIFIER ) = FALSE ) then
				exit function
			end if

			'' error recovery: fake a symbol
			sym = symbAddNamespace( hMakeTmpStr( ), NULL )
			id[0] = 0							'' id = ""
			chain_ = NULL

		'' id..
		else
			id = *lexGetText( )
			chain_ = lexGetSymChain( )
		end if

		'' already defined?
		if( chain_ <> NULL ) then
			sym = chain_->sym

			'' not a namespace?
			if( symbIsNamespace( sym ) = FALSE ) then
				if( errReportEx( FB_ERRMSG_DUPDEFINITION, id ) = FALSE ) then
					exit function
				else
					'' error recovery: fake an id
					id = *hMakeTmpStr( )
					sym = NULL
				end if

            else
				'' not the same hash tb?
				if( symbGetHashTb( sym ) <> symbGetCurrentHashTb( ) ) then
					'' then it's an inner ns with the same name as an outer one..
					sym = NULL
				end if
			end if


		else
			sym = NULL
		end if

		'' skip ID, don't lookup the '.'s
		if( id[0] <> 0 ) then
			lexSkipToken( LEXCHECK_NOLOOKUP )
		end if

		'' create a new symbol?
		if( sym = NULL ) then
			if( levels = 1 )  then
				'' (ALIAS LITSTR)?
				if( lexGetToken( ) = FB_TK_ALIAS ) then
    				lexSkipToken( )

					if( lexGetClass( ) <> FB_TKCLASS_STRLITERAL ) then
						if( errReport( FB_ERRMSG_SYNTAXERROR ) = FALSE ) then
							exit function
						end if

					else
						lexEatToken( @id_alias )
						palias = @id_alias
					end if
				end if
			end if

			sym = symbAddNamespace( @id, palias )
			if( sym = NULL ) then
				if( errReportEx( FB_ERRMSG_DUPDEFINITION, id ) = FALSE ) then
					exit function
				else
					'' error recovery: fake an id
					sym = symbAddNamespace( hMakeTmpStr( ), NULL )
				end if
			end if
		end if

		''
		stk = cCompStmtPush( FB_TK_NAMESPACE, _
						 	 FB_CMPSTMT_MASK_ALL and (not FB_CMPSTMT_MASK_CODE) _
						 					 	 and (not FB_CMPSTMT_MASK_EXTERN) _
						 					 	 and (not FB_CMPSTMT_MASK_DATA) )

		stk->nspc.node = astNamespaceBegin( sym )
		stk->nspc.levels = 1

		'' ALIAS used?
		if( palias <> NULL ) then
			exit do
		end if

		'' not a '.'?
		if( lexGetToken( ) <> CHAR_DOT ) then
			exit do
		end if

		lexSkipToken( LEXCHECK_NOLOOKUP )
	loop

	stk->nspc.levels = levels

	function = TRUE

end function

'':::::
''NamespaceStmtEnd  =     END NAMESPACE .
''
function cNamespaceStmtEnd as integer
	dim as FB_CMPSTMTSTK ptr stk = any
	dim as integer levels = any

	function = FALSE

	stk = cCompStmtGetTOS( FB_TK_NAMESPACE )
	if( stk = NULL ) then
		exit function
	end if

	'' END NAMESPACE
	lexSkipToken( )
	lexSkipToken( )

	levels = stk->nspc.levels

	do while( levels > 0 )
		'' back to parent
		astNamespaceEnd( stk->nspc.node )

		'' pop from stmt stack
		cCompStmtPop( stk )

		stk = cCompStmtGetTOS( FB_TK_NAMESPACE, FALSE )
		if( stk = NULL ) then
			exit do
		end if

		levels -= 1
	loop

	function = TRUE

end function

'':::::
''Usingtmt  =     USING ID (',' ID)*
''
function cUsingStmt as integer
    dim as FBSYMBOL ptr sym = any

    function = FALSE

    '' USING
    lexSkipToken( )

    do
    	'' ID
    	sym = cNamespace( FALSE )
    	if( sym = NULL ) then
    		if( lexGetToken( ) <> FB_TK_ID ) then
				if( errReport( FB_ERRMSG_EXPECTEDIDENTIFIER ) = FALSE ) then
					exit function
				else
					'' error recovery: skip until next ','
					hSkipUntil( CHAR_COMMA )
				end if

    		else
    			if( errReport( FB_ERRMSG_UNDEFINEDSYMBOL ) = FALSE ) then
    				exit function
				else
					'' error recovery: skip until next ','
					hSkipUntil( CHAR_COMMA )
				end if
			end if

    	else
			'' not a namespace?
			if( symbIsNamespace( sym ) = FALSE ) then
				if( errReport( FB_ERRMSG_TYPEMISMATCH ) = FALSE ) then
					exit function
				end if

			else
    			if( symbNamespaceImport( sym ) = FALSE ) then
	   				exit function
    			end if
			end if
		end if

    '' ','?
    loop while( hMatch( CHAR_COMMA ) )

    function = TRUE

end function

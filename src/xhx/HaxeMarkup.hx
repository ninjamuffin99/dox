package xhx;

import xhx.Data;
import xhx.HaxeLexer;
import hxparse.LexerStream;

class HaxeMarkup
{
	public inline static var DIRECTIVE = "directive";
	public inline static var KEYWORD = "keyword";
	public inline static var IDENTIFIER = "identifier";
	public inline static var STRING = "string";
	public inline static var CONSTANT = "constant";
	public inline static var COMMENT = "comment";
	public inline static var MACRO = "macro";
	public inline static var TYPE = "type";

	public static function markup(source:String, file:String)
	{
		if (source == "" || source == null) return "";
		var parser = new HaxeMarkup(source, file);
		source = parser.parse();
		return '<code><pre>$source</pre></core>';
	}

	var active:Bool;
	var defines:Map<String, Bool>;
	var source:String;
	var max:Int;
	var buf:StringBuf;
	var stream:LexerStream<Token>;
	var stack:Array<Bool>;

	public function new(source:String, file:String)
	{
		this.active = true;
		this.defines = new Map<String, Bool>();
		this.source = source;
		this.max = 0;
		this.buf = new StringBuf();
		this.stack = [];

		var input = new haxe.io.StringInput(source);
		stream = new LexerStream(new HaxeLexer(input, file), HaxeLexer.tok);

		defines.set("neko", true);
		defines.set("sys", true);
	}

	public function add(token:Token, ?span:String)
	{
		// add any non token chars to buffer (whitespace etc.)
		if (token.pos.min > max) buf.add(source.substring(max, token.pos.min));

		// add token string
		max = token.pos.max;
		var str = StringTools.htmlEscape(source.substring(token.pos.min, max));
		if (span == null) buf.add(str);
		else buf.add('<span class="$span">$str</span>');

		stream.junk();
	}

	function parseMacro():Bool
	{
		return true;
		
		var token = stream.peek();
		return switch (token.tok)
		{
			case Const(CIdent(s)):
				add(token, MACRO);
				defines.exists(s);
			case Kwd(Macro):
				add(token, MACRO);
				defines.exists(MACRO);
			case Unop(OpNot):
				add(token, MACRO);
				!parseMacro();
			case POpen:
				add(token, MACRO);
				var val = parseMacro();
				token = stream.peek();
				while (token.tok != Eof)
				{
					switch (token.tok)
					{
						case Binop(OpBoolAnd):
							add(token, MACRO);
							val = val && parseMacro();
						case Binop(OpBoolOr):
							add(token, MACRO);
							val = val || parseMacro();
						case PClose:
							add(token, MACRO);
							break;
						case _:
							throw "invalid macro condition " + token.tok;
					}
					token = stream.peek();
				}
				val;
			case _: false;
		}
	}

	public function parseTypeId():Bool
	{
		var tokens = [];
		var index = 0;
		var token = stream.peek();

		while (token.tok != Eof)
		{
			tokens.push(token);

			switch (token.tok)
			{
				case Const(CIdent(s)):
					var code = s.charCodeAt(0);
					if (code > 64 && code < 91)
					{
						for (token in tokens) add(token, TYPE);
						return true;
					}
				case Dot:
				case _:
					return false;
			}

			index += 1;
			token = stream.peek(index);
		}

		return false;
	}

	public function skipTokens()
	{
		var token = stream.peek();
		var start = stack.length;

		while (token.tok != Eof)
		{
			if (stack.length == start)
			{
				switch (token.tok)
				{
					case Sharp("elseif"), Sharp("else"), Sharp("end"): break;
					case _:
				}
			}
			
			switch (token.tok)
			{
				case Sharp("if"):
					add(token, MACRO);
					stack.unshift(parseMacro());
				case Sharp("elseif"):
					add(token, MACRO);
					if (!stack[0]) stack[0] = parseMacro();
				case Sharp("else"):
					add(token, MACRO);
					if (!stack[0]) stack[0] = true;
				case Sharp("end"):
					add(token, MACRO);
					stack.shift();
				case _:
					add(token, "inactive");
			}

			token = stream.peek();
		}
	}

	public function parse()
	{
		var token = stream.peek();

		while (token.tok != Eof)
		{
			switch (token.tok)
			{
				case Sharp(s):
					add(token, MACRO);

					if (s == "if")
					{
						stack.unshift(parseMacro());
						if (!stack[0]) skipTokens();
					}
					else if (s == "elseif")
					{
						var bool = parseMacro();
						if (stack[0])
						{
							skipTokens();
						}
						else
						{
							stack[0] = bool;
							if (!stack[0]) skipTokens();
						}
					}
					else if (s == "else")
					{
						if (stack[0])
						{
							skipTokens();
						}
						else
						{
							stack[0] = true;
						}
					}
					else if (s == "end")
					{
						stack.shift();
					}
				case Kwd(Class), Kwd(Import), Kwd(Enum), Kwd(Abstract), Kwd(Typedef), Kwd(Package):
					add(token, DIRECTIVE);
				case Kwd(_), Const(CIdent("trace")):
					add(token, KEYWORD); 
				case Const(CIdent(s)):
					if (!parseTypeId()) add(token, IDENTIFIER); 
				case Const(CString(_)):
					add(token, STRING); 
				case Const(_):
					add(token, CONSTANT); 
				case CommentLine(_), Comment(_):
					add(token, COMMENT); 
				case _:
					add(token);
			}
			
			token = stream.peek();
		}

		return buf.toString();
	}
}


enum HRToken{
	//Single-character tokens
    leftBracket; rightBracket; equals; comma; leftParen; rightParen;
	//Keywords
	variableSection; taskSection; templateSection;
	//DataTypes
	identifier; value;
	//other
	none; eof; double_dash;
}
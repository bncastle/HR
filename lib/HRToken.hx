package lib;

enum HRToken{
	//Single-character tokens
    leftBracket; rightBracket; equals; comma; leftParen; rightParen;
	//Keywords
	variableSection; taskSection; templateSection; useSection;
	//DataTypes
	identifier; value;
	//other
	none; eof; double_dash;
}
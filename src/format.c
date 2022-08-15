#include <string.h>
#include <stdio.h>
#include <stdlib.h>

char* format_word_wrap(char* input, int rows, int cols) {
	char* output = malloc(sizeof(char) * (strlen(input) * 2));
	char* this_word = malloc(sizeof(char) * (cols + 1));
	int row_cur = 0;
	int col_cur = 0;
	int newlines = 0;
	for(int i = 0; i < strlen(input); i++) {
		output[row_cur * rows + col_cur + newlines] = input[i];
		col_cur++;
		if(col_cur == cols) {
			strcat(output, "\n");
			newlines++;
			row_cur++;
			col_cur = 0;
		}
		if(row_cur == rows) {
			return output;
		}
	}
	return output;
}


void format_demo() {
	char* result = format_word_wrap("This is a test of the text formatting system. It better work...", 14, 14);
	printf("result: \n%s\n", result);
}
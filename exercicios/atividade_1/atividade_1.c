/*
========================================================================
Name					: atividade_1.c
Author				: Rafael Neves de Mello Oliveira
Copyright			:
Description		: Você deve escrever duas funções em C. Ambas devem receber
								como parâmetros um vetor V de inteiros e o tamanho do vetor,
								e retornar um valor do tipo double. A primeira função,
								denominada "media(int* lista, int tamanho)" deve retornar a
								média aritmética dos valores do vetor. Ex: se V = [9,8,6,4],
								o resultado deve ser 6.75. A segunda função, denominada
								"desvio(int* lista, int tamanho)" deve calcular o desvio
								padrão do vetor. Para o mesmo exemplo, o desvio padrão
								calculado deve ser 1.92.

Detalhes			: O tamanho do vetor V deverá ser fornecido na linha de comando
								(utilize os argumentos da função main() para isso);

								A função atoi() converte string em inteiro;

								As funções precisam ter os nomes e ordem de argumentos
								exatamente como solicitado;

								O vetor V deve ser alocado dinamicamente no código (utilize
								as funções malloc() e free());

								O vetor V deve ser inicializado com valores aleatórios
								(pesquise as funções srand() e rand() pra isso);
								Assuma a fórmula de desvio padrão populacional para cálculo
								do desvio padrão (pesquise as funções sqrt() e pow() da
								biblioteca math.h para uso no cálculo). Para isso, não
								esqueça de adicionar a opção -lm no momento da compilação;
								As funções "media()" e "desvio()" devem ser chamadas dentro
								da função main(). A média e desvio padrão calculados, assim
								como o conteúdo do vetor V, devem ser impressos na tela ao
								final da execução.
								Para compilar seu programa e preparar o envio no moodle,
								utilize o Makefile recomendado na página da disciplina:

								$ mkdir atividade_1
								$ cd atividade_1
								$ # copie o Makefile para este diretório e escreva seu programa
								$ make

								Correção automática
								O script grade-intro-c.sh corrige essa tarefa automaticamente
								e atribui uma nota. Uso do script:

								$ chmod +x grade-intro-c.sh # adiciona permissão de execução,
								só é preciso uma vez
								$ ./grade-intro-c.sh atividade_1

								Para que seu código receba nota 10 você precisará concluir um
								desafio. Para resolvê-lo você vai precisar das funções scanf()
								e realloc().

								Desafio
								Caso o programa não receba nenhum argumento de linha de comando
								(dica: argc == 1), leia os números (separados por espaço) da
								entrada padrão. Considere o fim da entrada (EOF) como o momento
								para parar a leitura (dica: scanf retornará 0) Exemplo:

								$ echo 1 2 3 | ./program
								Media = 2.0000
								Desvio padrao = 0.8165
								$

								No comando acima a barra "em pé" é chamada de pipe. A função
								dela é conectar a saída de um programa na entrada de outro. O
								programa echo simplesmentre imprime na saída os argumentos que
								ele recebe. Caso queira digitar os números diretamente, use ^D
								(Ctrl+D) para indicar o final de arquivo:

								$ program
								1 2 3
								^D
								Media = 2.0000
								Desvio padrao = 0.8165
								$

========================================================================
*/
// library that allows me to use 'srand()'
#include <time.h>
// library that allows me to use math functions
#include <math.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

double media(int* array, int arraySize);
double desvio(int* array, int arraySize);
void printArray(int* array, int arraySize);
double summation(double* array, int arraySize);
double sqtRoot(double value);
double* powerOfTwo (int* array, int arraySize);
void initiateArray(int* array, int arraySize);

// Main function
/*!
	Principal function on my program, here I call all the methods
	implemented. Check if there is any argument given when the program
	is runned.
	Receives the value of the size that is given by the command
	line using 'argv[]' property. I use 'atoi()' to convert a string
	to a int
*/
int main (int argc, char *argv[]) {
		int *array = NULL;
		int arraySize = 0;
	if (argc > 1) {  // With 'argc' values
		 // define the size of the array based on the value given in 'argc'
		arraySize = atoi(argv[1]);
		// locate the array with the size of the 'arraySize'
		array = malloc(sizeof(int[arraySize]));
		initiateArray(array, arraySize);
		printArray(array, arraySize);
	} else {  // without argc values (code from the answer given by the professor)
		int arraySizeDefault = 2;
		int value = 0;
		int status = 0;
		arraySize = 0;
		array =(int*) malloc(sizeof(int[arraySizeDefault]));

		while((status = scanf("%d", &value)) > 0) {
			if (arraySize == arraySizeDefault) {
				array = (int*)realloc(array, arraySizeDefault*2);
			}
			array[arraySize++] = value;
		}
		if (status == 0) {
			printf("ERROR: found a char %c\n ", getchar());
			return 1;
		}
		if (status != EOF) {
			printf("ERROR: %d while reading %s\n", errno, strerror(errno));
			return 1;
		}
	}
	printf("mean: %.2lf\n", (media(array, arraySize)));
	printf("Standard Deviation: %.2lf\n", (desvio(array, arraySize)));

	// Free the memory allocated for the array
	free(array);
	// Ends the program
	return 0;
}

//  Method that compute the arithmetic mean of a array given
/*!
	Calc the arithmetic mean
*/
double media(int* array, int arraySize){
	double meanValue = 0.0;
	for (int j = 0; j < arraySize; j++) {
		meanValue += array[j];
	}
	meanValue = meanValue/(double)arraySize;
	return meanValue;
}

// Standard Deviation
/*!
	Calc the standardDeviation of a given method
	1. instantiate the variables, to do that calls the "mean" function to get the
	value of the mean and apply to the variable "meanValue"
	2. compute the values of the array "array" given minus the "meanValue", then
	make the power of two of the result of this expression and add each value's
	result to the auxiliar array created "auxarray";
	3. Calls the "summation" function given as parameters the auxiliar array
	"auxarray" and it's size, make the square root of the value given back from
	the function called and then apply the value for the variable
	"standardDeviation" that will be returned
*/
double desvio(int* array, int arraySize) {
	double standardDeviation = 0.0;
	double meanValue = media(array, arraySize);
	double auxarray[arraySize];

	for(int i = 0; i < arraySize; i++) {
		auxarray[i] = pow((array[i]- meanValue), 2);
	}
	standardDeviation = sqrt((summation(auxarray, arraySize)));
	return standardDeviation;
}
//  Summation method
/*!
	Compute the summation of a array given and after that divide
	the value of the summation by the size of the array given
*/
double summation (double* array, int arraySize) {
	double summation = 0.0;

	for(int i = 0; i < arraySize; i++) {
		summation += array[i];
	}
	summation = (summation/arraySize);
	return summation;
}
// Initiate array function
/*!
	Fill an array, given by parameters, with random int numbers from 0 -10
*/
void initiateArray(int* array, int arraySize) {
	// Define a seed to generate random numbers based on the clock time
	srand(time(NULL));
	int i;
	for (i = 0; i < arraySize; i++) {
		array[i] = rand()%10;
	}
}

//  Print array method
/*!
	Print all the values in an array
*/
void printArray(int* array, int arraySize) {
	for(auto int j = 0; j < arraySize; j++) {
		printf("%i ", array[j] );
	}
	printf("%s\n", " ");
}

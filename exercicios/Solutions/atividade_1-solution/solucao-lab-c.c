/*
============================================================================
Name        : Ativ1.c
Author      : Frank
Version     : 1.0
Copyright   : Your copyright notice
Description : Calcula media e desvio padrao de array com numeros aleatorios
============================================================================
*/

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <errno.h>
#include <string.h>

#define DEFAULT_SIZE    5	// Tamanho default do array
#define MAX_VALUE     100 	// Valor maximo gerado aleatoriamente

// Calcula a media de um array de tamanho size
float media(int *array, int size) {
    float sum = 0;
    for (int i = 0; i < size; i++) {
        sum += array[i];
    }
    return (sum/(float)size);
}

// Calcula o desvio padrão de um array de tamanho size
float desvio(int * array, int size) {
    float avg = media(array, size);
    float sum = 0;
    for (int i = 0; i < size; i++) {
        sum += pow(array[i] - avg, 2)/size;
    }
    return sqrt(sum);
}

// Funcao principal do programa
int main(int argc, char *argv[]) {
    int *array = NULL;
    int size = 0;
    if (argc > 1) { // Se for passado algum valor na linha de comando...
        size = atoi(argv[1]);  // ... define o tamanho do array como sendo esse valor

        // Aloca memoria para o array com o tamanho especificado
        array = malloc(size*sizeof(int));

        // Define uma semente para geracao dos numeros aleatorios com base no relogio da maquina
        srand(time(NULL));

        // Preenche as posicoes do array com numeros aleatorios e os imprime na tela
        for (int i = 0; i < size; i++) {
            array[i] = rand() % MAX_VALUE;
            printf("array[%d] = %d\n", i, array[i]);
        }
    } else { // sem argumentos ... ler da entrada padrão
        size = 0; //numero de valores no vetor
        int reserved = DEFAULT_SIZE; //capacidade do vetor
        array = (int*)malloc(reserved*sizeof(int));
        int value = 0;
        int status = 0;
        while ((status = scanf(" %d", &value)) > 0) { //enquanto for lido um valor em value
            if (size == reserved) // array cheio
                array = (int*)realloc(array, size*2); //dobra a capacidade do array
            array[size++] = value; //adiciona value no final e incrementa size
        }
        if (status == 0) {
            printf("Esperava um número, encontrou %c\n", getchar());
            return 1;
        }
        if (status != EOF) {
            printf("Erro %d lendo a entrada: %s\n", errno, strerror(errno));
            return 1;
        }
        // fim da entrada (ou erro)
    }

    // Imprime a média dos valores contidos no array
    printf("Media = %.4f\n", media(array, size));

    // Imprime o desvio padrao dos valores contidos no array
    printf("Desvio padrao = %.4f\n", desvio(array, size));

    // Libera a memoria alocada para o array
    free(array);

    // Encerra o programa
    return 0;
}

/*!
    #pragma omp parallel [atributos]
                          private(var1, var2,...)
                          shared(var1, var2,...)
                          firstprivate(var1, var2,...)
                          reduction(operador: var1, var2,...)

    private(var1, var2,...): Declara que as variáveis serão de uso específico
                            de cada thread.
                            Essas variáveis não serão inicializadas.

                                   | a = -1
                                   |
                             ______|_______  omp parallel
                              |         |
                              |         |
                              | a1      | a2
                              |         |
                            __|_________|___
                                   |
                                   | a = -1
                                   |
                                   |
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------

    firstprivate(var1, var2,...): Declara qeu as variáveis serão de uso específico
                                  de cada thread.
                                  Inicializa com o valor que possuía antes da região
                                  paralela.

                                  | a = -1
                                  |
                            ______|_______  omp parallel
                             |         |
                             |         |
                             | a1=-1   | a2=-1
                             |         |
                           __|_________|___
                                  |
                                  | a = -1
                                  |
                                  |
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

    shared(var1, var2,...): Declara que as variáveis serão compartilhadas entre
                            as threads.
                            Um único enredeço de memória para cada variável.

                            | a
                            |
                      ______|_______  omp parallel
                       |         |
                       |         |
                       | a       | a
                       |         |
                     __|_________|___
                            |
                            | a
                            |
                            |
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
    reduction(operador: var1, var2, ...): é criada uma variável privada por thread
                                          para cada variável compartilhada
                                          especificada no atributo reduction

                                          Ao final da região paralela, uma operação
                                          de redução utilizando um operador é aplicada
                                          a todas as variáveis privadas e variáveis
                                          compartilhadas.

                                          O resultado final é escrito na variável
                                          compartilhada.

                                          Funciona somente para variáveis escalares
                                          (variáveis escalares = variaveis primitivas
                                          [int, char, boolen, etc, ...])

                            | a=1
                            |
                      ______|___________________________________  omp parallel
                       |              |               |
                       |              |               |
                       | a1           | a2            | a3
                       |              |               |
                     __|______________|_______________|__________
                            |
                            | a = a+a1+a2+a3
                            |
                            |
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
    OBSERVAÇÃO:   SE EU NÃO ESPECIFICAR O NUMERO DE THREADS QUE EU QUERO ELE
                  CRIARÁ O NUMERO DE THREADS DE ACORDO COM A QUANTIDADE DE CORES
                  QUE EU TIVER NO MEU PROCESSADOR
    BIBLIOTECA:
                          #include <omp.h>
    COMPILAÇÃO:
                          $ gcc atributos.c -fopenmp -o program
                          $ ./program 4
*/


#include <stdio.h>
#include <omp.h>  //OpenMp
#include <stdlib.h>  // atoi

int main (int argc, char **argv) {

  if (argc < 2 || argc > 2) {
    printf("Expected: ./program 'number'\n");
  } else {

    int num_threads = atoi(argv[1]);
    omp_set_num_threads(num_threads);
    int a = -1;
    int b = -1;
    int c = -1;
    int d = 1;
    /*!
      'private' diretiva exemplo
    */
    #pragma omp parallel private(a)
    printf("dentro: %d\n",a);
    printf("fora: %d\n\n", a);


    /*!
      'firstprivate' diretiva exemplo
    */
    #pragma omp parallel firstprivate(b)
    {
      printf("dentro: %d\n", b);
      b = 123;
    }
    printf("fora: %d\n\n", b);

    /*!
      'shared' diretiva exemplo
    */
    #pragma omp parallel shared(c)
    {
      printf("dentro antes: %d\n", c);
      c = omp_get_thread_num();
      printf("dentro depois: %d\n", c);
    }
    printf("fora: %d\n\n", c);

    /*!
      'reduction' diretiva exemplo
    */
    #pragma omp parallel reduction(+:d)
      d = d+2;
      printf("Resultado: %d\n", d);

  }


  return 0;
}

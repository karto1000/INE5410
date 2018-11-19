#include <stdio.h>
#include <sys/types.h>

int main (int argc, char* argv[]) {

	/*!
		atribui o valor, passado pelo prompt de comando, a
		variável NUM_THREADS.
		a funcao 'atoi()' converte um string para um 'int' 
	*/
	int NUM_THREADS = atoi(argv[1]);
	/*!
		'pthread_t' usado para identificar uma thread.
		'threads' vai ser um array de threads
	*/ 
	pthread_t threads[NUM_THREADS];
	for(int i = 0; NUM_THREADS; i++) {
		pthread_create()
	}

	return 0;
}
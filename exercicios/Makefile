NAME=atividade_8
GRADE_NAME=grade-threads
GRADE_DEPS:=$(wildcard ./testbench/*.*)

.PHONY: moodle all clean initial solution

all: moodle $(GRADE_NAME).sh

clean: 
	find . -name 'grade-*.sh' -delete || true
	find . -name '*~' -delete || true
	rm -f $(SUBGRADE_NAME).sh
	rm -fr moodle-tmp testbench-build
	rm -f $(NAME).tar.gz $(NAME)-solution.tar.gz
	cd solution && mvn clean
	cd initial && mvn clean



moodle: $(GRADE_NAME).sh
	find . -name '*~' -delete || true
	cd solution && mvn clean verify && mvn clean
	cd initial && mvn clean test-compile && mvn clean
	rm -fr moodle-tmp
	mkdir -p moodle-tmp
	cp -r initial moodle-tmp/$(NAME)
	rm -fr moodle-tmp/$(NAME)/*.iml moodle-tmp/$(NAME)/.idea moodle-tmp/$(NAME)/.classpath moodle-tmp/$(NAME)/test-output moodle-tmp/$(NAME)/dependency-reduced-pom.xml moodle-tmp/$(NAME)/.project
	cd moodle-tmp && tar zcf $(NAME).tar.gz $(NAME)
	mv moodle-tmp/$(NAME).tar.gz .
	rm -fr moodle-tmp
	mkdir -p moodle-tmp
	cp -r solution moodle-tmp/$(NAME)-solution
	rm -fr moodle-tmp/$(NAME)/*.iml moodle-tmp/$(NAME)/.idea moodle-tmp/$(NAME)/.classpath moodle-tmp/$(NAME)/test-output moodle-tmp/$(NAME)/dependency-reduced-pom.xml moodle-tmp/$(NAME)/.project
	cd moodle-tmp && tar zcf $(NAME)-solution.tar.gz $(NAME)-solution
	mv moodle-tmp/$(NAME)-solution.tar.gz .
	rm -fr moodle-tmp

$(GRADE_NAME).sh: $(GRADE_DEPS)
	rm -fr testbench-build
	cp -r testbench/ testbench-build
	cp -r solution testbench-build/timeout
	rm -fr testbench-build/timeout/target
	../../pack-grade.sh testbench-build $(GRADE_NAME).sh
	rm -fr testbench-build
	cp $(GRADE_NAME).sh initial/
	cp $(GRADE_NAME).sh solution/
	./$(GRADE_NAME).sh solution | grep 'Grade for solution: 10'
	./$(GRADE_NAME).sh initial | grep -E 'Grade for initial: [2-4]'

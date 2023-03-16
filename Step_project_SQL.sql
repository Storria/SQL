/*1. v1
Покажите среднюю зарплату сотрудников за каждый год
(средняя заработная плата среди тех, кто работал в отчетный период -статистика с начала до 2005 года).
*/
SELECT YEAR(from_date) AS year, ROUND(AVG(salary),2) AS avg_salary
FROM employees.salaries
WHERE YEAR(from_date) < 2006
GROUP BY YEAR(from_date)
ORDER BY year;

#1. v2
SELECT DISTINCT YEAR(from_date) AS year,
	   ROUND(AVG(salary) OVER (PARTITION BY YEAR(from_date)),2) AS avg_salary
FROM employees.salaries
WHERE YEAR(from_date) < 2006;

/*2. v1
Покажите среднюю зарплату сотрудников по каждому отделу.
Примечание: принять в расчет только текущие отделы и текущую заработную плату.
*/
SELECT dept_no, ROUND(AVG(salary),2) AS avg_salary
FROM (SELECT es.*, ede.dept_no
	  FROM employees.salaries AS es
      INNER JOIN employees.dept_emp AS ede
      ON(es.emp_no=ede.emp_no AND CURDATE() BETWEEN ede.from_date AND ede.to_date)
      WHERE CURDATE() BETWEEN es.from_date AND es.to_date) AS edes
GROUP BY dept_no
ORDER BY dept_no;

#2. v2
SELECT DISTINCT ede.dept_no,
				ROUND(AVG(es.salary) OVER (PARTITION BY ede.dept_no ORDER BY ede.dept_no),2) AS avg_salary
FROM employees.salaries AS es
INNER JOIN employees.dept_emp AS ede
ON(es.emp_no=ede.emp_no AND CURDATE() BETWEEN ede.from_date AND ede.to_date)
WHERE CURDATE() BETWEEN es.from_date AND es.to_date;

/*3.
Покажите среднюю зарплату сотрудников по каждому отделу за каждый год.
Примечание: для средней зарплаты отдела X в году Y нам нужно взять среднее значение
всех зарплат в году Y сотрудников,которые были в отделе X в году Y.
*/
SELECT dept_no, YEAR(from_date) AS year, ROUND(AVG(salary),2) AS avg_salary
FROM (SELECT es.*, ede.dept_no
	  FROM employees.salaries AS es
      INNER JOIN employees.dept_emp AS ede
      ON (es.emp_no=ede.emp_no
      AND YEAR(es.from_date) BETWEEN YEAR(ede.from_date) AND YEAR(ede.to_date))) AS edes
GROUP BY dept_no, year
ORDER BY dept_no;

#4.Покажите для каждого года самый крупный отдел (по количеству сотрудников) в этом году и его среднюю зарплату.
WITH dep_count_emp(year, dept_no, count_emp)
AS(SELECT DISTINCT YEAR(from_date) AS year, dept_no, 
		  COUNT(emp_no) OVER (PARTITION BY YEAR(from_date), dept_no) AS count_emp
   FROM employees.dept_emp)

SELECT dmc.year, dmc.dept_no, dmc.count_emp, eds.avg_salary AS dept_avg_salary
FROM (SELECT DISTINCT dce.year, dce.dept_no, max_emp.max_emp_count AS count_emp
	  FROM dep_count_emp AS dce
	  INNER JOIN (SELECT year, MAX(count_emp) OVER (PARTITION BY year) AS max_emp_count
				  FROM dep_count_emp) AS max_emp
	  ON(dce.year=max_emp.year AND dce.count_emp=max_emp.max_emp_count)) AS dmc
INNER JOIN (SELECT dept_no, YEAR(from_date) AS year, ROUND(AVG(salary),2) AS avg_salary
			FROM (SELECT es.*, ede.dept_no
				  FROM employees.salaries AS es
				  INNER JOIN employees.dept_emp AS ede USING(emp_no)) AS edes
                  GROUP BY dept_no, year
                  ORDER BY year) AS eds
ON(dmc.year=eds.year AND dmc.dept_no=eds.dept_no);

#5.Покажите подробную информацию о менеджере, который дольше всех исполняет свои обязанности на данный момент.
SELECT ee.*, manager.title, manager.from_date, manager.to_date, manager.days_as_manager
FROM employees.employees AS ee
INNER JOIN (SELECT *, TIMESTAMPDIFF(day,from_date,CURDATE()) AS days_as_manager
			FROM employees.titles
			WHERE title = 'Manager'
			AND CURDATE() BETWEEN from_date AND to_date
			ORDER BY days_as_manager DESC
			LIMIT 1) AS manager USING(emp_no);

/*6. v1
Покажите топ-10 нынешних сотрудников компании с наибольшей разницей между их зарплатой и
текущей средней зарплатой в их отделе.
*/
SELECT ede.emp_no,
	   es.salary,
       ede.dept_no,
       ROUND(AVG(salary) OVER (PARTITION BY dept_no),2) AS avg_dept_salary,
       ABS(es.salary - ROUND(AVG(salary) OVER (PARTITION BY dept_no),2)) AS diff
FROM employees.dept_emp AS ede
INNER JOIN employees.salaries AS es ON(ede.emp_no=es.emp_no
AND CURDATE() BETWEEN ede.from_date AND ede.to_date)
WHERE CURDATE() BETWEEN es.from_date AND es.to_date
ORDER BY diff DESC
LIMIT 10;

#6. v2
WITH cur_dept_sal (emp_no, salary, dept_no)
AS (SELECT es.emp_no, es.salary, ede.dept_no
	FROM employees.salaries AS es
	INNER JOIN employees.dept_emp AS ede USING (emp_no)
	WHERE CURDATE() BETWEEN ede.from_date AND ede.to_date
	AND CURDATE() BETWEEN es.from_date AND es.to_date)

SELECT emp_no, salary, dept_no, avg_dept_salary, difference
FROM (SELECT cds.emp_no, cds.salary, ads.dept_no, ads.avg_dept_salary,
             ABS(cds.salary - ads.avg_dept_salary) AS difference,
             ROW_NUMBER() OVER (ORDER BY ABS(cds.salary - ads.avg_dept_salary) DESC) AS row_no
	  FROM cur_dept_sal AS cds
      INNER JOIN (SELECT dept_no, ROUND(AVG(salary),2) AS avg_dept_salary
				  FROM cur_dept_sal
                  GROUP BY dept_no) AS ads USING(dept_no)) AS sal_dif
WHERE row_no <=10;


/*7.
Из-за кризиса на одно подразделение на своевременную выплату зарплаты выделяется всего 500 тысяч долларов.
Правление решило, что низкооплачиваемые сотрудники будут первыми получать зарплату.
Показать список всех сотрудников, которые будут вовремя получать зарплату
(обратите внимание, что мы должны платить зарплату за один месяц, но в базе данных мы храним годовые суммы).
*/
SELECT *
FROM (SELECT dept_no, emp_no, month_salary,
			 SUM(month_salary) OVER (PARTITION BY dept_no ORDER BY dept_no, month_salary) AS budget_control
	 FROM (SELECT de.dept_no, es.emp_no, es.salary,
				  ROUND(SUM(es.salary/12) OVER (PARTITION BY dept_no, es.emp_no ORDER BY es.salary),2) AS month_salary
		   FROM employees.salaries AS es
           LEFT JOIN employees.dept_emp AS de
           ON (de.emp_no=es.emp_no AND CURDATE() BETWEEN de.from_date AND de.to_date)
           WHERE CURDATE() BETWEEN es.from_date AND es.to_date) AS monsal
	 ) AS sumsalary
 WHERE budget_control < 500000;

/*Дизайн базы данных:1.
Разработайте базу данных для управления курсами. База данных содержит следующие сущности:
a.students: student_no, teacher_no, course_no, student_name, email, birth_date.
b.teachers: teacher_no, teacher_name, phone_no
c.courses: course_no, course_name, start_date, end_date.
●Секционировать по годам, таблицу students по полю birth_date с помощью механизма range
●В таблице students сделать первичный ключ в сочетании двух полей student_no и birth_date
●Создать индекс по полю students.email
●Создать уникальный индекс по полю teachers.phone_no
*/
CREATE DATABASE IF NOT EXISTS courses;

USE courses;

CREATE TABLE IF NOT EXISTS teachers(
	teacher_no INT PRIMARY KEY AUTO_INCREMENT,
    teacher_name VARCHAR(50) NOT NULL,
    phone_no CHAR(16) NOT NULL);
    
CREATE TABLE IF NOT EXISTS courses(
	course_no INT PRIMARY KEY AUTO_INCREMENT,
    course_name VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL);

CREATE TABLE IF NOT EXISTS students(
	student_no INT AUTO_INCREMENT,
    teacher_no INT,
    course_no INT,
    student_name VARCHAR(50) NOT NULL,
    email VARCHAR(50) NOT NULL,
    birth_date DATE,
	PRIMARY KEY (student_no, birth_date))
    PARTITION BY RANGE (YEAR(birth_date))
	(PARTITION y85 VALUES LESS THAN (1986),
	PARTITION y86 VALUES LESS THAN (1987),
	PARTITION y87 VALUES LESS THAN (1988),
	PARTITION y88 VALUES LESS THAN (1989),
	PARTITION y89 VALUES LESS THAN (1990),
	PARTITION y90 VALUES LESS THAN (1991),
	PARTITION y91 VALUES LESS THAN (1992),
	PARTITION y92 VALUES LESS THAN (1993),
	PARTITION y93 VALUES LESS THAN (1994),
	PARTITION y94 VALUES LESS THAN (1995),
	PARTITION y95 VALUES LESS THAN (1996),
	PARTITION y96 VALUES LESS THAN (1997),
	PARTITION y97 VALUES LESS THAN (1998),
	PARTITION y98 VALUES LESS THAN (1999),
	PARTITION y99 VALUES LESS THAN (2000),
	PARTITION y00 VALUES LESS THAN (2001),
	PARTITION y01 VALUES LESS THAN MAXVALUE);

CREATE INDEX ind_email ON courses.students(email);

CREATE UNIQUE INDEX unique_phone ON courses.teachers(phone_no);

#2.На свое усмотрение добавить тестовые данные (7-10 строк) в наши три таблицы.
INSERT INTO teachers(teacher_name, phone_no)
VALUES('Edd Auld', '+38-161-167-6172'),
	  ('Kym Pinching', '+38-177-979-4733'),
      ('Frederic Deacock', '+38-116-424-9100'),
      ('Fredra Wittier', '+38-278-885-4789'),
      ('Elnora McClements', '+38-326-373-3583'),
      ('Naomi Scholcroft', '+38-220-554-7823'),
      ('Germaine Denziloe', '+38-445-734-0675'),
      ('Hal Lavell', '+38-737-525-3443'),
      ('Shadow Waren', '+38-289-858-3471'),
      ('Jakob Rickerby', '+38-870-760-2963');

SELECT *
FROM courses.teachers;

INSERT INTO courses(course_name, start_date, end_date)
VALUES('SQL', '2022-09-01', '2022-09-30'),
	  ('ETL', '2022-10-01', '2022-10-14'),
      ('Python', '2022-10-15', '2022-11-15'),
      ('Tableau', '2022-11-16', '2022-11-30'),
      ('POWER BI', '2022-12-11', '2022-12-25'),
      ('ADD COURSE 1', '2023-01-10', '2023-01-31'),
      ('ADD COURSE 2', '2023-02-01', '2023-02-26');
      
SELECT *
FROM courses.courses;
      
INSERT INTO students(teacher_no, course_no, student_name, email, birth_date)
VALUES(6, 6, 'Giusto Bladge', 'gbladge0@google.fr', '1994-11-05'),
	  (8, 2, 'Merrick Marian', 'mmarian1@google.com', '2001-12-21'),
      (6, 2, 'Evvie Martin', 'emartin2@eepurl.com', '1997-03-15'),
      (10, 4, 'Tull Kinsman', 'tkinsman3@utexas.edu', '1994-09-05'),
      (4, 7, 'Con Bolte', 'cbolte4@addthis.com', '1989-12-12'),
      (2, 6, 'Jessey Lithgow', 'jlithgow5@examiner.com', '1992-03-16'),
      (5, 3, 'Israel Cotterill', 'icotterill7@163.com', '1991-05-19'),
      (9, 1, 'Deck Jersh', 'djersh6@reuters.com', '1986-03-06'),
      (10, 3, 'Arabele Burtonshaw', 'aburtonshaw8@bbc.co.uk', '1989-03-27'),
      (6, 5, 'Weider Yerlett', 'wyerlett9@constantcontact.com', '1985-03-11');
      
SELECT *
FROM courses.students;
      
/*3.Отобразить данные за любой год из таблицы students и зафиксировать в виду 
комментария план выполнения запроса, где будет видно что запрос будет выполняться по конкретной секции.
*/
SELECT *
FROM courses.students PARTITION(y92);

EXPLAIN SELECT *
FROM courses.students PARTITION(y92);

/*
# id, select_type, table, partitions, type, possible_keys, key, key_len, ref, rows, filtered, Extra
'1', 'SIMPLE', 'students', 'y92', 'ALL', NULL, NULL, NULL, NULL, '1', '100.00', NULL
*/

/*4.Отобразить данные учителя, по любому одному номеру телефона и зафиксировать план выполнения запроса,
где будет видно, что запрос будет выполняться по индексу, а не методом ALL. 
Далее индекс из поля teachers.phone_no сделать невидимым и зафиксировать план выполнения запроса,
где ожидаемый результат - метод ALL. В итоге индекс оставить в статусе -видимый. 
*/
EXPLAIN SELECT *
FROM courses.teachers
WHERE phone_no = '+38-278-885-4789';

/*
# id, select_type, table, partitions, type, possible_keys, key, key_len, ref, rows, filtered, Extra
'1', 'SIMPLE', 'teachers', NULL, 'const', 'unique_phone', 'unique_phone', '64', 'const', '1', '100.00', NULL
*/

ALTER TABLE courses.teachers
ALTER INDEX unique_phone INVISIBLE;

EXPLAIN SELECT *
FROM courses.teachers
WHERE phone_no = '+38-278-885-4789';

/*
# id, select_type, table, partitions, type, possible_keys, key, key_len, ref, rows, filtered, Extra
'1',  'SIMPLE',   'teachers', NULL,   'ALL',  NULL,        NULL, NULL,   NULL, '10', '10.00', 'Using where'
*/

ALTER TABLE courses.teachers
ALTER INDEX unique_phone VISIBLE;

#5.Специально сделаем 3 дубляжа в таблице students (добавим еще 3 одинаковые строки).
INSERT INTO students(teacher_no, course_no, student_name, email, birth_date)
VALUES(8, 2, 'Merrick Marian', 'mmarian1@google.com', '2001-12-21'),
	  (8, 2, 'Merrick Marian', 'mmarian1@google.com', '2001-12-21'),
      (8, 2, 'Merrick Marian', 'mmarian1@google.com', '2001-12-21');

SELECT *
FROM courses.students;
      
#6. v1 Написать запрос, который выводит строки с дубляжами.
SELECT teacher_no, course_no, student_name, email, birth_date
FROM courses.students
GROUP BY teacher_no, course_no, student_name, email, birth_date
HAVING COUNT(student_no) > 1;

#6. v2
SELECT *
FROM (SELECT *,
			COUNT(student_no) OVER (PARTITION BY teacher_no, course_no, student_name, email, birth_date) AS check_doubles
	  FROM courses.students) AS count_doubles
WHERE check_doubles > 1;

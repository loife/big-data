### O projektu

Projekat je rađen u okviru predmeta **Računarstvo u oblaku**. Cilj je bio implementirati platformu za prikupljanje, procesiranje, čuvanje i analizu podataka sa društvenih mreža i blog portala, hostovanu na AWS platformi. Obrada podataka prati **Medalion arhitekturu**, odnosno podaci prolaze kroz tri sloja: bronze, silver i gold.

Podaci se prikupljaju sa dva izvora: **Hacker News** portala i **X (Twitter)** platforme.

### Arhitektura

Tok obrade podataka izgleda ovako:

1. **Hacker News** i **X** su izvori podataka koje prikupljaju Lambda funkcije i upisuju u **S3 (bronze)** u sirovom obliku.
2. Lambda funkcija normalizuje podatke iz bronze sloja i čuva ih u **S3 (silver)** u parquet formatu.
3. Lambda funkcija transformiše silver podatke u metrike i KPI, koji se čuvaju u **S3 (gold)**.
4. Lambda funkcija premešta podatke iz gold sloja u **PostgreSQL** bazu na EC2 instanci.
5. **Apache Superset**, takođe na EC2, povezuje se na bazu i prikazuje vizualizacije.

### Bronze layer - prikupljanje podataka

Prikupljanje se radi preko Lambda funkcija, po jedna za svaki izvor podataka.

- **Hacker News** - dnevno se prikupljaju sve objave, pitanja, komentari, ponude za posao i ankete kreirane prethodnog dana, preko javnog Hacker News API-ja.
- **X (Twitter)** - zbog ograničenja besplatnog API-ja, koriste se postojeći ili ručno formirani/generisani dataset-ovi.

Podaci se upisuju u S3 bucket u izvornom, nepromenjenom obliku - bronze sloj ne uključuje nikakvu transformaciju.

### Silver layer - normalizacija podataka

Lambda funkcija svodi podatke iz bronze sloja na jedinstvenu šemu i format. Normalizacija obuhvata:

- poravnanje ugnežđenih struktura, 
- poravnanje formata vremena u jedinstven UTC format,
- čišćenje HTML tagova iz sadržaja,
- uklanjanje duplikata,
- uspostavljanje šeme podataka (tabele `users` i `posts`) usklađene sa 3NF.

Normalizovani podaci se čuvaju u **parquet** formatu, particionisano po platformi i vremenu.

### Gold layer - transformacija podataka

Lambda funkcija izračunava metrike i KPI na osnovu silver sloja, među kojima:

- broj objava, pitanja, komentara, poslova i anketa po danu na Hacker News-u,
- broj korisnika po danu, po platformi,
- top 10 korisnika X platforme po broju pratilaca,
- top 10 korisnika Hacker News-a po najvišem i najnižem karma score-u,
- top 10 poslova i objava po score-u,
- **Data Quality Score** - procenat popunjenih (ne-null) vrednosti u tabelama, kao indikator kvaliteta normalizacije.

Rezultati se čuvaju u gold sloju kao parquet fajlovi, organizovani po Star Schema modelu i particionisani po platformi i datumu.

### Vizualizacija

Metrike i KPI iz gold sloja se preko Lambda funkcije prebacuju u **PostgreSQL** bazu, hostovanu na EC2 instanci. Nad tom bazom je povezan **Apache Superset**, takođe hostovan na EC2, koji služi za vizualizaciju podataka.

### Notifikacije

Sistem šalje notifikacije na Discord server u slučaju da neki od job-ova (Lambda funkcija) ne uspe da se izvrši.

### Infrastruktura

Celokupna infrastruktura je definisana kroz Infrastructure as Code pristup, a sav mrežni saobraćaj je ograničen unutar VPC mreže uz primenu principa najmanjih privilegija - dozvoljena je isključivo neophodna komunikacija između servisa preko sigurnosnih grupa i mrežnih pravila.

### Tehnologije

AWS (Lambda, S3, EC2, VPC), PostgreSQL, Apache Superset, parquet format, Discord webhook notifikacije, Docker (containerizovan deployment Lambda funkcija).
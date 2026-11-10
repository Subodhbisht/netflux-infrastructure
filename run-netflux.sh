mvn -f ../movie-service/pom.xml clean package
mvn -f ../user-account-service/pom.xml clean package
mvn -f ../recommendation-service/pom.xml clean package

docker compose build 

docker compose up
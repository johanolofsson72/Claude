FROM mcr.microsoft.com/dotnet/aspnet:latest
WORKDIR /app
COPY ./publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Shop.Api.dll"]

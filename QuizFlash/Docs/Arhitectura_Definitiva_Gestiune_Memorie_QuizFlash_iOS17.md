Arhitectura Definitiva de Gestiune a Memoriei SwiftData si SwiftUI pe
iOS 17

Document de referinta si instructiuni stricte pentru asistentii AI si
dezvoltatorii viitori.

1.  Scopul Documentului

Acest document detaliaza solutia arhitecturala care garanteaza
stabilitatea memoriei RAM in aplicatia QuizFlash pe iOS 17 si implicit
iOS 18.

Orice cod nou generat pentru aceasta aplicatie trebuie sa respecte
regulile de izolare a datelor descrise aici.

Nerespectarea lor va reintroduce memory leaks si crash-uri de tip Out Of
Memory.

2.  Anatomia Problemelor pe iOS 17

Pe iOS 17, ecosistemul SwiftData si SwiftUI sufera de doua bug-uri
critice de tip retain cycle care duc la cresterea progresiva a memoriei.

Bug A The Main Context Row Cache Trap

Cand un View SwiftUI sau un ViewModel pe MainActor apeleaza direct o
relatie SwiftData cum ar fi Array deck.cards, ModelContext-ul principal
incarca toate obiectele CardModel in registeredObjects, adica identity
map sau row cache.

Din cauza ObservationRegistrar din iOS 17, chiar daca View-ul este
distrus prin navigare inapoi, referinta invizibila catre acele modele nu
este taiata.

Contextul principal pastreaza obiectele Model in RAM la infinit.

Bug B The ModelActor Zombie Context

Folosirea macro-ului standard ModelActor creeaza automat un ModelContext
de fundal.

Pe iOS 17, acest context se inregistreaza ascuns in NotificationCenter
pentru a asculta schimbarile bazei de date.

Cand actorul este distrus, contextul din interiorul sau nu este
dealocat.

El ramane un Zombie Context tinut in viata de NotificationCenter,
blocand in memorie toate imaginile si datele grele citite.

3.  Solutia Arhitecturala The Isolated Flushable Actor

Pentru a ocoli limitarile iOS 17, este implementata o arhitectura
stricta bazata pe patru piloni.

Pilonul 1 Actor Custom fara Macro

Se renunta complet la macro-ul ModelActor.

Se creeaza un actor standard, de exemplu CardFetchActor, in care
ModelContext-ul este instantiat si gestionat manual.

Pilonul 2 Flush RAM prin recrearea contextului

SwiftData nu expune o functie publica de resetare a contextului.

Singura metoda reala de golire a memoriei cache este distrugerea
completa a contextului si recrearea lui.

Se implementeaza o functie privata flushRAM care creeaza un ModelContext
nou si il inlocuieste pe cel vechi.

Efectul este distrugerea instantanee a contextului anterior, ruperea
legaturilor cu NotificationCenter si eliberarea imediata a memoriei
ocupate de imagini si modele.

Pilonul 3 Detached Flat Fetch

MainActor-ul nu are voie sa atinga direct un array de CardModel.

DeckViewModel cere datele de la CardFetchActor.

Actorul de fundal citeste deck.cards, extrage doar textele si valorile
necesare si le mapeaza intr-o structura usoara si sigura concurential,
de tip GridCardInfo marcata Sendable.

Imediat dupa mapare, actorul apeleaza flushRAM.

Actorul returneaza catre MainActor doar array-ul de structuri usoare.

Efectul este mentinerea contextului principal curat si evitarea
incarcarii inutile de CardModel in memorie.

Pilonul 4 True Lazy Loading si Garbage Collection Manual

Imaginile sau alte date media sunt incarcate exclusiv la afisarea pe
ecran, la cerere.

Cand elementul iese de pe ecran, datele media sunt setate explicit la
nil pentru a forta dealocarea.

La inchiderea ecranului se goleste manual NSCache si se apeleaza metoda
tearDown a actorului pentru a distruge ultimul context de fundal.

4.  Directive pentru Asistentii AI

Fara macro-ul ModelActor. Nu se genereaza niciodata cod folosind
ModelActor.

Regula Sendable Boundary. Niciun obiect SwiftData de tip Model nu are
voie sa traverseze granita dintre actorul de fundal si MainActor. Se
transfera exclusiv structuri value type marcate Sendable.

Fara relatii iterate pe Main Thread. In ViewModel pe MainActor este
interzis sa se faca loop peste relatii to many precum deck.cards. Aceste
operatii se delega actorului de fundal. Contextul principal este folosit
doar pentru insert, delete si save.

Teardown obligatoriu. Orice clasa care initializeaza un actor SwiftData
trebuie sa implementeze metoda tearDown apelata in onDisappear. Aceasta
metoda trebuie sa invoce flushRAM in interiorul actorului.

Eliberare media. Orice LazyVGrid sau LazyVStack care randeaza date grele
precum Data sau UIImage trebuie sa seteze acele proprietati la nil in
onDisappear pentru a garanta eliberarea memoriei pe iOS 17.

Concluzie

Aceasta arhitectura este obligatorie pentru stabilitatea aplicatiei
QuizFlash pe iOS 17.

Orice abatere de la aceste reguli va reintroduce memory leaks, crestere
progresiva a memoriei RAM si crash-uri de tip Out Of Memory.

import {AresJournal} from '../journal.mjs';
const store=new AresJournal({directory:process.argv[2]});
try {process.stdout.write(JSON.stringify(store.begin(JSON.parse(process.argv[3]))));}
finally {store.close();}

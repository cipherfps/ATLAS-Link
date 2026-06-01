const sails = require('sails');
const NeoLog = require('./structs/NeoLog');
const { default: axios } = require('axios');
const fs = require("fs").promises;
const path = require("path");
const { execSync } = require('child_process');
const version = require('./package.json').version;

async function compareAndUpdateKeychain() {
  const keychain = JSON.parse(await fs.readFile("./responses/keychain.json", "utf-8"));
  const response = await axios.get('https://fortnitecentral.genxgames.gg/api/v1/aes', { validateStatus: () => true });
  if (response.status === 200) {
    const data = response.data;

    let missingCount = 0;
    const keychainArray = [];

    for (const keys of data.dynamicKeys) {
      if (!keychain.includes(keys.keychain)) {
        missingCount++;
        keychainArray.push(keys.keychain);
      }
    }
    keychain.push(...keychainArray);

    await fs.writeFile("./responses/keychain.json", JSON.stringify(keychain, null, 2));
    NeoLog.Debug(`Fetched ${missingCount} New Keychains from Fortnite Central.`);
  }
  else if (response.status !== 200) {
    NeoLog.Error("Fortnite Central is down, falling back to dillyapis for the keychain");
    const fallbackResponse = await axios.get('https://export-service.dillyapis.com/v1/aes', { validateStatus: () => true });
    if (fallbackResponse.status === 200) {
      const data = fallbackResponse.data
      let missingCount = 0;
      const keychainArray = [];

      for (const keys of data.dynamicKeys) {
        if (!keychain.includes(keys.keychain)) {
          missingCount++;
          keychainArray.push(keys.keychain);
        }
      }
      keychain.push(...keychainArray);
      await fs.writeFile("./responses/keychain.json", JSON.stringify(keychain, null, 2));
      NeoLog.Debug(`Fetched ${missingCount} New Keychains From dillyapis`);
    }
    else {
      NeoLog.Error("Unable to connect to both Fortnite Central and dillyapis! Falling back to existing keychains on your local disk. You may experience issues!");
    }
  }
}

function updateBackend() {
  const zip = path.join(__dirname, 'update.zip');
  const temp = path.join(__dirname, 'temp');      

  return axios.get('https://raw.githubusercontent.com/HybridFNBR/Neonite/refs/heads/main/package.json', { validateStatus: undefined }).then((response) => {
    if (response.status == 200) {
      if (response.data.version > version) {
        NeoLog.Log(`Update Available, Any Modified files will be Overrwritten - Downloading Update(Patch: ${response.data.version})`);
         const cmd = `powershell -Command "Invoke-WebRequest -Uri 'https://github.com/HybridFNBR/Neonite/archive/refs/heads/main.zip' -OutFile '${zip}'; Expand-Archive -Path '${zip}' -DestinationPath '${temp}' -Force; Copy-Item -Path '${temp}\\*\\*' -Destination '${__dirname}' -Recurse -Force -Exclude 'app.js'; Remove-Item '${zip}' -Force; Remove-Item '${temp}' -Recurse -Force"`;
        try {
          execSync(cmd, { stdio: 'inherit' });
          NeoLog.Debug(`Finished Updating to Patch ${response.data.version}`);
        } catch (err) {
          NeoLog.Error(err);
        }
      }
    }
  });
}

async function startBackend() {
  sails.lift({
    port: 5595,
    environment: "production",
    hooks: {
      session: false,
    },
    log: {
      level: 'silent',
    },
  }, (err) => {
    if (err) {
      console.log(err);
    }
  });
}

async function runFunctions() {
  await updateBackend();
  await compareAndUpdateKeychain();
  await startBackend();
}
runFunctions();

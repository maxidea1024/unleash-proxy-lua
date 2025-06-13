// ----------------------------------------------------------------------------
// COPYRIGHT (C)2017 BY MOTIF CO., LTD. ALL RIGHTS RESERVED.
// ----------------------------------------------------------------------------

import ToggletClient from './toggletClient';
import mconf from '../mconf';
import { getGitRevisionInfo } from '../mutil';
import { hostname } from 'os';
import { getLocalIp, getPublicIp } from './ip';

let togglet: ToggletClient | undefined;

async function initTogglet(): Promise<void> {
  if (togglet) {
    destroyTogglet();
  }

  const environment = process.env.NODE_ENV || 'development';

  const gitRevisionInfo = getGitRevisionInfo();
  const serverBuildBranch = gitRevisionInfo.branch ?? '<unknown>';
  const serverHostname = hostname();
  const serverCommitDate = new Date(gitRevisionInfo.date).toISOString() ?? '<unknown>';
  const serverCommitHash = gitRevisionInfo.git_rev ? gitRevisionInfo.git_rev.substring(0, 7) : '<unknown>';

  const serverExternalAddress = await getPublicIp();
  const serverInternalAddress = getLocalIp();

  togglet = new ToggletClient({
    // TODO 환경변수에서 가져오는 형태로 하던지..
    apiUrl: 'https://us.app.unleash-hosted.com/usii0012/api/',
    accessToken: '*:development.8d662424920812bad929a7f778d607a00779c75a2e8a25575541d5f3',
    environment,
    appName: process.name,
    defaultContext: {
      appName: process.name,
      environment,
      properties: {
        serverHostname,
        serverBuildBranch,
        serverCommitDate,
        serverCommitHash,
        serverExternalAddress,
        serverInternalAddress,
        binaryCode: mconf.binaryCode,
        countryCode: mconf.countryCode,
        serverType: process.name,
        worldId: mconf.worldId,
      },
    },
  });

  await togglet.init();
}

function destroyTogglet() {
  if (togglet) {
    togglet.destroy();
    togglet = undefined;
  }
}

export { togglet, initTogglet, destroyTogglet };

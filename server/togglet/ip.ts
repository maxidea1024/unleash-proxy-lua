import axios, { AxiosResponse } from 'axios';
import os from 'os';

const IP_SERVICES: string[] = [
  'http://metadata.tencentyun.com/latest/meta-data/public-ipv4', // Tencent Cloud metadata (only inside Tencent CVM)
  // 'http://ip.cn/api/index?type=0',
  // 'http://ip138.com/iplookup.asp',
  'https://api.ipify.org?format=json',
  'https://ipinfo.io/json',
  'https://checkip.amazonaws.com'
];

type IpApiResponse = {
  ip?: string;
  IP?: string;
  IPv4?: string;
  address?: string;
  ip_address?: string;
  [key: string]: any;
};

function extractIpFromHtml(html: string): string | null {
  const regex = /(?:您的IP地址|您的IP)：(?:&nbsp;)?(\d{1,3}(?:\.\d{1,3}){3})/;
  const match = regex.exec(html);
  return match ? match[1] : null;
}

async function fetchIpFromUrl(url: string): Promise<string> {
  try {
    const response: AxiosResponse = await axios.get(url, { timeout: 4000 });

    if (url.includes('metadata.tencentyun.com')) {
      if (typeof response.data === 'string') {
        return response.data.trim();
      }
      throw new Error('Invalid response format from Tencent metadata service');
    }

    if (url.includes('ip.cn')) {
      const json: IpApiResponse = response.data;
      if (json && json.ip) return json.ip;
      throw new Error('No IP found in ip.cn response');
    }

    if (url.includes('ip138.com')) {
      const html = response.data as string;
      const ip = extractIpFromHtml(html);
      if (ip) return ip;
      throw new Error('Failed to extract IP from ip138.com HTML');
    }

    if (url.includes('amazonaws.com') || url.includes('checkip.amazonaws.com')) {
      if (typeof response.data === 'string') {
        return response.data.trim();
      }
      throw new Error('Response is not in text format');
    }

    if (typeof response.data === 'object') {
      const json: IpApiResponse = response.data;
      const ip = json.ip || json.IP || json.IPv4 || json.address || json.ip_address;
      if (!ip) throw new Error('No IP found in JSON response');
      return ip;
    }

    throw new Error('Unsupported response format');
  } catch (err) {
    throw new Error(`Failed to fetch IP from ${url}: ${(err as Error).message}`);
  }
}

export async function getPublicIp(fallbackIp = '255.255.255.255'): Promise<string> {
  for (const url of IP_SERVICES) {
    try {
      const ip = await fetchIpFromUrl(url);
      return ip;
    } catch (err) {
      // console.warn(`[WARN] Failed to fetch IP from ${url}: ${(err as Error).message}`);
    }
  }
  return fallbackIp;
}

export function getLocalIp(preferredFamily: 'IPv4' | 'IPv6' = 'IPv4'): string {
  const interfaces = os.networkInterfaces();
  const results: string[] = [];

  for (const name of Object.keys(interfaces)) {
    const networkInterface = interfaces[name];

    if (!networkInterface) {
      continue;
    }

    for (const interfaceInfo of networkInterface) {
      if (interfaceInfo.internal) {
        continue;
      }

      // Check if the address family matches our preference
      const isPreferredFamily =
        (preferredFamily === 'IPv4' && interfaceInfo.family === 'IPv4') ||
        (preferredFamily === 'IPv6' && interfaceInfo.family === 'IPv6');

      if (isPreferredFamily) {
        results.push(interfaceInfo.address);
      }
    }
  }

  if (results.length > 0) {
    return results[0];
  }

  const otherFamily = preferredFamily === 'IPv4' ? 'IPv6' : 'IPv4';
  return getLocalIp(otherFamily);
}

export function getAllLocalIps(): { [key: string]: string[] } {
  const interfaces = os.networkInterfaces();
  const results: { [key: string]: string[] } = {
    IPv4: [],
    IPv6: []
  };

  for (const name of Object.keys(interfaces)) {
    const networkInterface = interfaces[name];

    if (!networkInterface) {
      continue;
    }

    for (const interfaceInfo of networkInterface) {
      if (interfaceInfo.internal) {
        continue;
      }

      if (interfaceInfo.family === 'IPv4') {
        results.IPv4.push(interfaceInfo.address);
      } else if (interfaceInfo.family === 'IPv6') {
        results.IPv6.push(interfaceInfo.address);
      }
    }
  }

  return results;
}

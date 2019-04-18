# 2018.05.11 - changed the implementation for classes of GcpSession and
#              GcpModule
#            - changed the name of some variables
#            - changed remove_nones_from_dict
#
# Copyright (c), Google Inc, 2017
# Simplified BSD License (see licenses/simplified_bsd.txt or
# https://opensource.org/licenses/BSD-2-Clause)

import time
import re

try:
    import logging
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

try:
    from keystoneauth1.adapter import Adapter
    from keystoneauth1.identity import v3
    from keystoneauth1 import session
    HAS_THIRD_LIBRARIES = True
except ImportError:
    HAS_THIRD_LIBRARIES = False

from ansible.module_utils.basic import AnsibleModule, env_fallback
from ansible.module_utils._text import to_text


class HwcClientException(Exception):
    def __init__(self, code, message):
        super(HwcClientException, self).__init__()

        self._code = code
        self._message = message

    def __str__(self):
        msg = " code=%s," % str(self._code) if self._code != 0 else ""
        return "[HwcClientException]%s message=%s" % (
            msg, self._message)


class HwcClientException404(HwcClientException):
    def __init__(self, message):
        super(HwcClientException404, self).__init__(404, message)

    def __str__(self):
        return "[HwcClientException404] message=%s" % self._message


def session_method_wrapper(f):
    def _wrap(*args, **kwargs):
        try:
            r = f(*args, **kwargs)
        except Exception as ex:
            raise HwcClientException(
                0, "Sending request failed, error=%s" % ex)

        result = None
        if r.content:
            try:
                result = r.json()
            except Exception as ex:
                raise HwcClientException(
                    0, "Parsing response to json failed, error: %s" % ex)

        code = r.status_code
        if code not in [200, 201, 202, 203, 204, 205, 206, 207, 208, 226]:
            msg = ""
            for i in ['message', 'error.message']:
                try:
                    msg = navigate_value(result, i)
                    break
                except Exception:
                    pass
            else:
                msg = str(result)

            if code == 404:
                raise HwcClientException404(msg)

            raise HwcClientException(code, msg)

        return result

    return _wrap


# Handles all authentation and HTTP sessions for HWC API calls.
class HwcSession(object):
    def __init__(self, client, endpoint, product):
        self._client = client
        self._endpoint = endpoint
        self._default_header = {
            'User-Agent': "Huawei-Ansible-MM-%s" % product,
            'Accept': 'application/json',
        }

    @session_method_wrapper
    def get(self, url, body=None, header=None):
        return self._client.get(url, json=body, raise_exc=False,
                                headers=self._header(header))

    @session_method_wrapper
    def post(self, url, body=None, header=None):
        return self._client.post(url, json=body, raise_exc=False,
                                 headers=self._header(header))

    @session_method_wrapper
    def delete(self, url, body=None, header=None):
        return self._client.delete(url, json=body, raise_exc=False,
                                   headers=self._header(header))

    @session_method_wrapper
    def put(self, url, body=None, header=None):
        return self._client.put(url, json=body, raise_exc=False,
                                headers=self._header(header))

    def _header(self, header):
        if header and isinstance(header, dict):
            for k, v in self._default_header.items():
                if k not in header:
                    header[k] = v
        else:
            header = self._default_header

        return header


class Config(object):
    def __init__(self, module, product):
        self._project_client = None
        self._domain_client = None
        self._module = module
        self._product = product
        self._endpoints = {}

        self._validate()
        self._gen_provider_client()

    @property
    def module(self):
        return self._module

    def client(self, region, service_type, service_level):
        c = self._project_client
        if service_level == "domain":
            c = self._domain_client

        e = self._get_service_endpoint(c, service_type, region)

        return HwcSession(c, e, self._product)

    def _gen_provider_client(self):
        logger = self._init_log()
        m = self._module
        p = {
            "auth_url": m.params['identity_endpoint'],
            "password": m.params['password'],
            "username": m.params['user_name'],
            "project_name": m.params['project_name'],
            "user_domain_name": m.params['domain_name'],
            "reauthenticate": True
        }

        self._project_client = Adapter(
            session.Session(auth=v3.Password(**p)), logger=logger)

        p.pop("project_name")
        self._domain_client = Adapter(
            session.Session(auth=v3.Password(**p)), logger=logger)

    def _get_service_endpoint(self, client, service_type, region):
        k = "%s.%s" % (service_type, region if region else "")

        if k in self._endpoints:
            return self._endpoints.get(k)

        e = None
        try:
            e = client.get_endpoint_data(service_type=service_type,
                                         region_name=region)
        except Exception as ex:
            raise HwcClientException(
                0, "Getting endpoint failed, error=%s" % ex)

        if not e or e.url == "":
            raise HwcClientException(
                0, "Can not find the enpoint for %s" % service_type)

        url = e.url
        if url[-1] != "/":
            url += "/"

        self._endpoints[k] = url
        return url

    def _init_log(self):
        log_file = self._module.params['log_file']
        if not log_file:
            return None

        try:
            log = logging.getLogger()
            log.setLevel(logging.DEBUG)

            fh = logging.FileHandler(log_file, mode='a')
            fh.setLevel(logging.DEBUG)
            fh.setFormatter(logging.Formatter(
                "%(asctime)s - %(filename)s[line:%(lineno)d] - %(levelname)s: "
                "%(message)s"))
            log.addHandler(fh)

            return log
        except Exception as ex:
            raise HwcClientException(
                0, "Initiating module log failed, err=%s" % ex)

    def _validate(self):
        if not HAS_REQUESTS:
            raise HwcClientException(0, "Please install the requests library")

        if not HAS_THIRD_LIBRARIES:
            raise HwcClientException(
                0, "Please install the keystoneauth1 library")


class HwcModule(AnsibleModule):
    def __init__(self, *args, **kwargs):
        arg_spec = kwargs.setdefault('argument_spec', {})

        arg_spec.update(
            dict(
                identity_endpoint=dict(
                    required=True, type='str',
                    fallback=(env_fallback, ['IDENTITY_ENDPOINT']),
                ),
                user_name=dict(
                    required=True, type='str',
                    fallback=(env_fallback, ['USER_NAME']),
                ),
                password=dict(
                    required=True, type='str', no_log=True,
                    fallback=(env_fallback, ['PASSWORD']),
                ),
                domain_name=dict(
                    required=True, type='str',
                    fallback=(env_fallback, ['DOMAIN_NAME']),
                ),
                project_name=dict(
                    required=True, type='str',
                    fallback=(env_fallback, ['PROJECT_NAME']),
                ),
                region=dict(
                    required=True, type='str',
                    fallback=(env_fallback, ['REGION']),
                ),
                log_file=dict(
                    type='str',
                    fallback=(env_fallback, ['LOG_FILE']),
                ),
                timeouts=dict(type='dict', options=dict(
                    create=dict(default='10m', type='str'),
                    update=dict(default='10m', type='str'),
                    delete=dict(default='10m', type='str'),
                ), default={}),
                id=dict(type='str')
            )
        )

        super(HwcModule, self).__init__(*args, **kwargs)


# This class takes in two dictionaries `a` and `b`.
# These are dictionaries of arbitrary depth, but made up of standard Python
# types only.
# Note: On all lists, order does matter.
class DictComparison(object):
    def __init__(self, request):
        self.request = request

    def __eq__(self, other):
        return self._compare_dicts(self.request, other.request)

    def __ne__(self, other):
        return not self.__eq__(other)

    def _compare_dicts(self, dict1, dict2):
        if set(dict1.keys()) != set(dict2.keys()):
            return False

        for k in dict1:
            if not self._compare_value(dict1.get(k), dict2.get(k)):
                return False

        return True

    # Takes in two lists and compares them.
    def _compare_lists(self, list1, list2):
        if len(list1) != len(list2):
            return False

        for i in range(len(list1)):
            if not self._compare_value(list1[i], list2[i]):
                return False

        return True

    def _compare_value(self, value1, value2):
        """
        return: True: value1 is same as value2, otherwise False.
        """
        if not (value1 and value2):
            return (not value1) and (not value2)

        # Can assume non-None types at this point.
        if isinstance(value1, list) and isinstance(value2, list):
            return self._compare_lists(value1, value2)

        elif isinstance(value1, dict) and isinstance(value2, dict):
            return self._compare_dicts(value1, value2)

        try:
            # Always use to_text values to avoid unicode issues.
            # to_text may throw UnicodeErrors. These errors shouldn't crash
            # Ansible and return False as default.
            return to_text(value1) == to_text(value2)
        except (UnicodeError, Exception):
            return False


def wait_to_finish(target, pending, refresh, timeout, min_interval=1, delay=3):
    is_last_time = False
    not_found_times = 0
    wait = 0

    time.sleep(delay)

    end = time.time() + timeout
    while not is_last_time:
        if time.time() > end:
            is_last_time = True

        obj, status = refresh()

        if obj is None:
            not_found_times += 1

            if not_found_times > 10:
                raise Exception(
                    "not found the object for %d times" % not_found_times)
        else:
            not_found_times = 0

            for s in target:
                if status == s:
                    return obj

            if pending:
                for s in pending:
                    if status == s:
                        break
                else:
                    raise Exception("unexpect status(%s) occured" % status)

        if not is_last_time:
            wait *= 2
            if wait < min_interval:
                wait = min_interval
            elif wait > 10:
                wait = 10

            time.sleep(wait)

    raise Exception("asycn wait timeout after %d seconds" % timeout)


def navigate_value(data, index, array_index):
    d = data
    for n in range(len(index)):
        if not isinstance(d, dict):
            raise Exception("can't navigate value from a non-dict object")

        i = index[n]
        if i not in d:
            raise Exception("navigate value failed: key(%s) "
                            "is not exist in dict" % i)
        d = d[i]

        if not array_index:
            continue

        j = array_index.get(".".join(index[: (n + 1)]))
        if j:
            if not isinstance(d, list):
                raise Exception("can't navigate value from a non-list object")

            if j >= len(d):
                raise Exception("navigate value failed: "
                                "the index is out of list")
            d = d[j]

    return d


def build_path(module, path, kv={}):
    v = {}
    for p in re.findall(r"{[^/]*}", path):
        n = p[1:][:-1]

        if n in kv:
            v[n] = str(kv[n])

        else:
            if n in module.params:
                v[n] = str(module.params.get(n))
            else:
                v[n] = ""

    return path.format(**v)


def get_region(module):
    return module.params['project_name'].split("_")[0]

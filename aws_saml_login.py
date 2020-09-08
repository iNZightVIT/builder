#!/usr/local/bin/python3

# Original: https://s3.amazonaws.com/awsiammedia/public/sample/SAMLAPICLIADFS/samlapi_formauth.py
# based of this post: https://aws.amazon.com/blogs/security/how-to-implement-a-general-solution-for-federated-apicli-access-using-saml-2-0/
# Massively changed by Robert Egglestone
# Some more tinkering by Justin Adam Susans

import sys
import re
import argparse
import boto3
import requests
import getpass
import configparser
import base64
import logging
import subprocess
import os
import http.client as http_client
import mechanicalsoup
from bs4 import BeautifulSoup
from os.path import expanduser
from urllib.parse import urlparse, urlunparse

parser = argparse.ArgumentParser(description='Obtain an AWS access key from a SAML login')
parser.add_argument('--credsfile', help='The AWS credentials file to use, defaults to ~/.aws/credentials')
parser.add_argument('--profile', default='saml', help='The profile to create in the credentials file, defaults to saml')
parser.add_argument('--idp', help='The identity provider base URL, this is a shortcut for --idpentryurl')
parser.add_argument('--idpentryurl', help='The full initial URL that starts the authentication process')
parser.add_argument('--role', help='Role to use must contain this string')
parser.add_argument('--account', help='String used to break ties if multiple results are returned by role')
parser.add_argument('--keychain', action='store_true', help='Use the OSX Keychain to obtain a password')
parser.add_argument('--oathtool', action='store_true', help='Use oathtool to obtain a multi-factor token')
parser.add_argument('--user', help='Username, defaults to logged in user')
parser.add_argument('--password', help='Password for user. If not passed as input will prompt. Recommend to input as a ENV variable rather than plaintext')
parser.add_argument('--token', help='token for user. If not passed as input will prompt. Best suited for service accounts with static tokens')
parser.add_argument('-v', '--verbose', action='count', default=0)
args = parser.parse_args()

accountDict = {
"337243602341":"UoA Identity",
"416527880812":"UoA Sandbox",
"031665005645":"UoA Tooling",
"810365525504":"UoA IoT",
"092829094803":"UoA WorkSpaces",
"723442535308":"UoA Security",
"801934657318":"UoA Master Billing",
"087951382964":"UoA Backup",
"518380838815":"UoA ITS Non Prod",
"291148375163":"UoA ITS Prod",
"332077666055":"UoA Law Non-Prod",
"166819473780":"UoA Law Prod",
"530174631580":"UoA Art Non-Prod",
"809365716064":"UoA Art Prod",
"868136143489":"UoA Science Non-Prod",
"630143336532":"UoA Science Prod",
"514211533206":"UoA Cer Non-Prod",
"985254009220":"UoA Cer Prod",
"879439455347":"UoA Fhms Non-Prod",
"889163251321":"UoA Fhms Prod",
"043576593226":"UoA Cai Non-Prod",
"648119695951":"UoA Cai Prod",
"761382414926":"UoA Business School Non-Prod",
"927818661880":"UoA Business School Prod",
"012961728893":"UoA Engineering Non-Prod",
"458166306323":"UoA Engineering Prod",
"422557767698":"UoA Esw Non-Prod",
"030770969999":"UoA Esw Prod",
"045652749769":"UoA Liggins Non-Prod",
"695565733611":"UoA Liggins Non-Prod",
"486491440557":"UoA Bioeng Non-Prod",
"248439654662":"UoA Bioeng Prod",
"167209821487":"UoA Library Non-Prod",
"727038065389":"UoA Library Prod"
}

# awscredsfile: The file where this script will store the temp credentials under the saml profile
awscredsfile = expanduser("~") + '/.aws/credentials'
if (args.credsfile): awscredsfile = args.credsfile

# profile: Profile section in credentials file
profile = args.profile

# idpentryurl: The initial url that starts the authentication process.
#idpentryurl = 'https://<fqdn>:<port>/idp/profile/SAML2/Unsolicited/SSO?providerId=urn:amazon:webservices'
idpentryurl = None
if not (args.idp or args.idpentryurl):
	print('Please set either --idp or --idpentryurl. Recommended default is \'--idp iam.auckland.ac.nz\'')
	sys.exit(1)
if (args.idpentryurl): idpentryurl = args.idpentryurl
if (args.idp): idpentryurl = args.idp + '/profile/SAML2/Unsolicited/SSO?providerId=urn:amazon:webservices'
if '://' not in idpentryurl:
	idpentryurl = 'https://' + idpentryurl

# role_selector: A filter on which role to select
role_selector = None
if (args.role): role_selector = args.role

account_selector = None
if (args.account): account_selector = args.account

# keychain: Whether we use the OSX Keychain to obtain credentials
keychain = bool(args.keychain)

# oathtool: Whether we use oathtool to obtain a multi-factor token
oathtool = bool(args.oathtool)

# Uncomment to enable low level debugging
verbosity = args.verbose
if verbosity >= 2: logging.basicConfig(level=logging.DEBUG)
if verbosity >= 3: http_client.HTTPConnection.debuglevel = 1

# Print config
if verbosity >= 1:
	print('Options')
	print(f"awscredsfile: {awscredsfile}")
	print(f"profile: {profile}")
	print(f"keychain: {keychain}")
	print(f"idpentryurl: {idpentryurl}")
	print(f"verbosity: {verbosity:d}")
	print()

# Get the username
def get_username():
	# todo: if keychain, get username from the keychain too
	return args.user or getpass.getuser()

# Get the user password
def get_password():
	password = None
	if (args.password):
		password = args.password
	elif keychain:
		host = urlparse(idpentryurl).netloc
		password = subprocess.check_output(['/usr/bin/security', 'find-generic-password', '-s', host, '-w']).decode('utf-8').strip()
	else:
		password = getpass.getpass('Password: ')
	if not password:
		print('Cannot obtain password')
		sys.exit(1)
	return password

# Get a multi-factor token
def get_mfa_token():
	if (args.token):
		mftoken = args.token
	elif oathtool and keychain:
		host = 'otp.' + '.'.join(urlparse(idpentryurl).netloc.split('.')[1:])
		mfsecret = subprocess.check_output(['/usr/bin/security', 'find-generic-password', '-s', host, '-w']).decode('utf-8').strip()
		mftoken = subprocess.check_output(['/usr/bin/env', 'oathtool', '--totp', '-b', '-d', '6', mfsecret]).decode('utf-8').strip()
	else:
		mftoken = getpass.getpass('Multi-factor token: ')
	if not mftoken:
		print('Cannot obtain multi-factor token')
		sys.exit(1)
	return mftoken

# Create browser
browser = mechanicalsoup.StatefulBrowser()
browser.session.trust_env = False
#browser.set_verbose(2)

# Visit the login page
browser.open(idpentryurl)
if 'Login' not in browser.get_current_page().title.string:
	print("Expecting login page but not found")
	sys.exit(1)
if verbosity >= 1: print(f"At login page: {browser.get_url()}")

# Fill in the login form
loginForm = browser.get_current_page().select('input[name="j_username"]')[0].find_parent('form')
browser.select_form(loginForm)
browser['j_username'] = get_username()
browser['j_password'] = get_password()
#print(browser.get_current_form().print_summary())
browser.submit_selected()

if not browser.get_current_page():
	print("Failed to submit login page")
	print(browser)
	sys.exit(1)

# Check if multi-factor is needed
token_fields = browser.get_current_page().select('input[name="j_token"]')
if token_fields:
	if verbosity >= 1: print(f"At multi-factor page: {browser.get_url()}")
	browser.select_form(token_fields[0].find_parent('form'))
	browser['j_token'] = get_mfa_token()
	#print(browser.get_current_form().print_summary())
	browser.submit_selected()
	
	if browser.get_current_page().select('input[name="j_token"]'):
		print('Multi-factor auth failed, did you re-authenticate too quickly?')
		sys.exit(1)

# Check for the SAML response
if not browser.get_current_page().select('form[action="https://signin.aws.amazon.com/saml"]'):
	print('Expecting SAML response but not found')
	sys.exit(1)

# Extract the SAML response
if verbosity >= 1: print(f"At SAML response: {browser.get_url()}")
saml_response_b64 = browser.get_current_page().select('input[name="SAMLResponse"]')[0].get('value')
saml_response = BeautifulSoup(base64.b64decode(saml_response_b64), 'xml')
#print(saml_response)

# Extract the AWS roles
awsroles_attrs = saml_response.select('Attribute[Name="https://aws.amazon.com/SAML/Attributes/Role"] AttributeValue')
awsroles = [ x.string for x in awsroles_attrs ]
#print(awsroles)

# Filter the roles if we have a selector
if role_selector:
	awsroles = [it for it in awsroles if role_selector in it]

sortedRoles = {}
matchKey = []
# Validate roles
if not awsroles:
	print("No valid AWS role found")
	sys.exit(1)
elif len(awsroles) > 1:
	if account_selector:
		for it in awsroles: 
			account = re.findall(r'\d{12}', it)
			accCommonName = accountDict[account[0]]
			shortRole = it.rsplit('/', 1)[-1]
			sortedRoles[accCommonName+" - "+shortRole] = it
		for key, value in sortedRoles.items():
			values = re.findall(r'(' + account_selector + ')', key, re.I)
			if (len(values) > 0):
				matchKey.append(key)
		if (len(matchKey) > 1):
			print("Multiple AWS roles found, please apply a role selector with --role or --account to select one of the below")
			for name in matchKey:
				print(f"\t{name}")
			sys.exit(1)
		elif (len(matchKey) == 0):
			print("No matches found on filters --role or --account. Try without one of the filters to see the available items")
			sys.exit(1)
		else:
			awsrole = sortedRoles[matchKey[0]]
	else:
		print("Multiple AWS roles found, please apply a role selector with --role or --account to select one of the below")
		for it in awsroles: 
			account = re.findall(r'\d{12}', it)
			accCommonName = accountDict[account[0]]
			shortRole = it.rsplit('/', 1)[-1]
			shortName = accCommonName+"-"+shortRole
			print(f"\t{shortName}")
		sys.exit(1)
else:
	awsrole = awsroles[0]
(principal_arn, role_arn) = awsrole.split(',')
if verbosity >= 1: print(f"Selected AWS role {role_arn}")

# Use the assertion to get an AWS STS token using Assume Role with SAML
sts = boto3.client('sts')
token = sts.assume_role_with_saml(RoleArn=role_arn, PrincipalArn=principal_arn, SAMLAssertion=saml_response_b64)
#print(token)

# Prepare Directory if not already existing to stop errors
awsDirectory = awscredfile = os.path.dirname(awscredsfile)
if not os.path.exists(awsDirectory):
	try:
		print(f"Attempting to create required directory, {awsDirectory}")
		os.makedirs(awsDirectory)
	except OSError as e:
		print("Issue with creating required directory. Please try again.")

# Write the AWS STS token into the AWS credential file
# Read in the existing config file
config = configparser.RawConfigParser()
config.read(awscredsfile)

# Put the credentials into a saml specific section instead of clobbering
# the default credentials
if not config.has_section(profile):
	config.add_section(profile)
config.set(profile, 'aws_access_key_id', token['Credentials']['AccessKeyId'])
config.set(profile, 'aws_secret_access_key', token['Credentials']['SecretAccessKey'])
config.set(profile, 'aws_session_token', token['Credentials']['SessionToken'])

# Write the updated config file
with open(awscredsfile, 'w+') as configfile:
	config.write(configfile)

# Give the user some basic info as to what has just happened
print (f"A temporary credential has been obtained for accessing AWS.")
print (f"To use this credential, call the AWS CLI with the --profile {profile} option.")
print (f"The token will expire at {token['Credentials']['Expiration']}.")
print ('After this time, you may safely rerun this script to refresh your access key pair.')

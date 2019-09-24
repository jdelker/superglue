Notes on whois metadata
=======================

Registr*s represent contact details in similar but not entirely
consistent ways.


EPP RFC 5733
------------

This is an outline of the contact information spec:

      <contact:postalInfo>
        <contact:name/>
        <contact:org/>?
        <contact:addr>
          <contact:street/>?
          <contact:street/>?
          <contact:street/>?
          <contact:city/>
          <contact:sp/>?
          <contact:pc/>?
          <contact:cc/>
        </contact:addr>
		<contact:voice/>?
		<contact:fax/>?
		<contact:email/>?
      </contact:postalInfo>


JANET / JISC
------------

The domain owner cannot be modified through the web UI, and instead
requires a letter on headed notepaper.

Element names on domain contact information page:

  * Name
  * Phone
  * Email
  * Fax
  * Add
  * Add1
  * Add2
  * Town
  * County
  * PostCode

Element names on domain contact modification form:

  * Name
  * Tel
  * Email
  * Fax
  * Add1
  * Add2
  * Add3
  * Town
  * County
  * Postcode


Mythic Beasts - .uk
-------------------

The registrant / domain owner cannot be modified through the web UI,
and instead we must use Nominet's web UI and pay a fee.

The contact information page has unlabelled fields in the same order
as the modification form, all prefixed with `registrant_`.

  * org (unmodifiable)
  * name
  * street0
  * street1
  * street2
  * city
  * sp (county)
  * pc (postcode)
  * cc (country, drop-down list)
  * voice (phone)
  * email


Mythic Beasts - other
---------------------

As for .uk, the contact information page has unlabelled fields in the
same order as the modification form. There are sections for

  * Registrant (in the text) / `owner_` (in the form)
  * Admin contact / `admin_`
  * Billing contact / `billing_`
  * Technical contact / `tech_`

Superglue fills these all in with the same details. We use the org /
company field to hold the owner / registrant, seperate from the named
contact.

  * first (First Name)
  * last (Last Name)
  * org (Company)
  * phone
  * fax
  * email
  * add1
  * add2
  * add3
  * city
  * county
  * postcode
  * country


Gandi (REST)
------------

The JSON contacts object has four fields, `owner`, `admin`, `bill`, `tech`.
Each sub-object has the fields:

  * given
  * family
  * orgname ?
  * streetaddr
  * city ?
  * state ?
  * zip ?
  * country
  * phone ?
  * fax ?
  * email
  * type

For controlling whois privacy:

  * data_obfuscated
  * mail_obfuscated

Problems:

  * Looks like we can't update the owner information with the REST API

  * Multiple address lines are joined with CRLF for the owner by
    commas for the other contacts

  * The `state` field takes a UN LOCODE rather than the normal
    human-readable value, e.g. `GB-CAM` is Cambridgeshire. For our
    purposes it can be omitted.

  * The `type` is a numeric code, 0 for people. I think we only need
    non-zero values for the domain owner. `orgname` only applies to
    non-zero types.

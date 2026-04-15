defmodule Yugo.ParserTest do
  use ExUnit.Case, async: true
  alias Yugo.Parser
  doctest Yugo.Parser

  test "tagged responses" do
    [tagged_response: {123, :ok, "CAPABILITY completed"}] =
      Parser.parse_response("123 OK CAPABILITY completed\r\n")
  end

  test "parse capabilities" do
    [
      capabilities: [
        "IMAP4REV1",
        "SASL-IR",
        "LOGIN-REFERRALS",
        "ID",
        "ENABLE",
        "IDLE",
        "LITERAL+",
        "AUTH=PLAIN"
      ]
    ] =
      Parser.parse_response(
        "* CAPABILITY IMAP4rev1 SASL-IR LOGIN-REFERRALS ID ENABLE IDLE LITERAL+ AUTH=PLAIN\r\n"
      )

    [capabilities: []] = Parser.parse_response("* capability         \r\n")
  end

  test "parse command continuation request" do
    [:continuation] = Parser.parse_response("+ continue...\r\n")
    [:continuation] = Parser.parse_response("+ \r\n")
  end

  test "parse untagged SELECT responses" do
    [permanent_flags: ["\\DELETED", "\\SEEN", "\\*"]] =
      Parser.parse_response("* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n")

    [permanent_flags: []] =
      Parser.parse_response("* OK [PERMANENTFLAGS ()] No permanent flags permitted\r\n")

    [first_unseen: 12] = Parser.parse_response("* OK [UNSEEN 12] Message 12 is first unseen\r\n")

    [uid_validity: 3_857_529_045] =
      Parser.parse_response("* OK [UIDVALIDITY 3857529045] UIDs valid\r\n")

    [uid_next: 4392] = Parser.parse_response("* OK [UIDNEXT 4392] Predicted next UID\r\n")

    [applicable_flags: ["\\ANSWERED", "\\FLAGGED", "\\DELETED", "\\SEEN", "\\DRAFT"]] =
      Parser.parse_response("* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")

    [applicable_flags: []] = Parser.parse_response("* FLAGS () nope no flags\r\n")
  end

  test "parse FETCH responses" do
    [
      fetch: {123, :flags, []}
    ] = Parser.parse_response(~S|* 123 fetch (flags ())|)

    [
      fetch:
        {12, :envelope,
         %{
           bcc: [],
           cc: [{nil, "minutes@cnri.reston.va.us"}, {"John Klensin", "klensin@mit.edu"}],
           date: ~U[1996-07-16 19:23:25Z],
           from: [{"Terry Gray", "gray@cac.washington.edu"}],
           in_reply_to: nil,
           message_id: "<B27397-0100000@cac.washington.edu>",
           reply_to: [{"Terry Gray", "gray@cac.washington.edu"}],
           sender: [{"Terry Gray", "gray@cac.washington.edu"}],
           subject: "IMAP4rev1 WG mtg summary and minutes",
           to: [{nil, "imap@cac.washington.edu"}]
         }},
      fetch: {12, :flags, ["\\Seen"]}
    ] =
      Parser.parse_response(
        ~S|* 12 FETCH (FLAGS (\Seen) ENVELOPE ("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)" "IMAP4rev1 WG mtg summary and minutes" (("Terry Gray" NIL "gray" "cac.washington.edu")) (("Terry Gray" NIL "gray" "cac.washington.edu")) (("Terry Gray" NIL "gray" "cac.washington.edu")) ((NIL NIL "imap" "cac.washington.edu")) ((NIL NIL "minutes" "CNRI.Reston.VA.US")("John Klensin" NIL "KLENSIN" "MIT.EDU")) NIL NIL "<B27397-0100000@cac.washington.edu>"))|
      )

    [fetch: {0, :flags, ["\\Seen", "\\Recent"]}, fetch: {0, :uid, 84}] =
      Parser.parse_response(~S|* 0 fetch (UID 84 FLags (\Seen \Recent))|)
  end

  test "parse FETCH (BODYSTRUCTURE) multipart response" do
    result =
      Parser.parse_response(
        ~S|* 456 FETCH (BODYSTRUCTURE (("text" "plain" ("charset" "UTF-8") NIL NIL "quoted-printable" 42 3 NIL NIL NIL NIL)("application" "pdf" NIL NIL NIL "base64" 5309722 NIL ("attachment" ("filename" "Dokument 1.pdf")) NIL NIL) "mixed" ("boundary" "sgnirk-bda7db69-ed50-4f7e-80a5-3ae818f88dd0") NIL NIL NIL) ENVELOPE ("Fri, 10 Apr 2026 11:40:02 +0000" "Test" ((NIL NIL "kuehn-praxis" "gmx.de")) ((NIL NIL "kuehn-praxis" "gmx.de")) ((NIL NIL "kuehn-praxis" "gmx.de")) ((NIL NIL "debug" "corporatesponsoring.de")) NIL NIL NIL "<trinity-1c175fcc-6802-4ca6-9a2f-4b50a916d923-1775821202071@trinity-msg-rest-gmx-gmx-live-5cf7d7879b-gcqxr>"))|
      )

    assert [
             fetch: {456, :envelope, _envelope},
             fetch:
               {456, :body_structure,
                {:multipart,
                 [
                   {:onepart,
                    %{
                      mime_type: "text/plain",
                      encoding: "QUOTED-PRINTABLE",
                      params: %{"charset" => "UTF-8"},
                      octets: 42,
                      lines: 3
                    }},
                   {:onepart,
                    %{
                      mime_type: "application/pdf",
                      encoding: "BASE64",
                      octets: 5_309_722,
                      params: %{"name" => "Dokument 1.pdf"}
                    }}
                 ]}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) simple text response" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "plain" ("charset" "us-ascii") NIL NIL "7bit" 1234 56 NIL NIL NIL NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/plain",
                   encoding: "7BIT",
                   params: %{"charset" => "us-ascii"},
                   octets: 1234,
                   lines: 56,
                   id: nil,
                   description: nil
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with MD5 hash" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "plain" ("charset" "utf-8") NIL NIL "quoted-printable" 500 25 "d41d8cd98f00b204e9800998ecf8427e" NIL NIL NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/plain",
                   encoding: "QUOTED-PRINTABLE",
                   params: %{"charset" => "utf-8"},
                   octets: 500,
                   lines: 25
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with inline disposition" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("image" "png" NIL "<image001@example.com>" "Company Logo" "base64" 12345 NIL ("inline" ("filename" "logo.png")) NIL NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "image/png",
                   encoding: "BASE64",
                   params: %{"name" => "logo.png"},
                   id: "<image001@example.com>",
                   description: "Company Logo",
                   octets: 12345
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with attachment disposition" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("application" "octet-stream" ("name" "data.bin") NIL NIL "base64" 98765 NIL ("attachment" ("filename" "data.bin" "size" "98765")) NIL NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "application/octet-stream",
                   encoding: "BASE64",
                   params: %{"name" => "data.bin"},
                   octets: 98765
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with single language string" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "plain" ("charset" "iso-8859-1") NIL NIL "8bit" 256 10 NIL NIL "de" NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/plain",
                   encoding: "8BIT",
                   params: %{"charset" => "iso-8859-1"},
                   octets: 256,
                   lines: 10
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with language list" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 1024 50 NIL NIL ("en" "de" "fr") NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/plain",
                   encoding: "7BIT",
                   params: %{"charset" => "utf-8"},
                   octets: 1024,
                   lines: 50
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with location URI" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "html" ("charset" "utf-8") NIL NIL "quoted-printable" 2048 100 NIL NIL NIL "https://example.com/newsletter.html"))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/html",
                   encoding: "QUOTED-PRINTABLE",
                   params: %{"charset" => "utf-8"},
                   octets: 2048,
                   lines: 100
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) with all optional fields populated" do
    # text/plain with: md5, disposition (inline), language list, and location
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("text" "plain" ("charset" "utf-8" "format" "flowed") "<content-id@example.com>" "Main body text" "quoted-printable" 4096 200 "098f6bcd4621d373cade4e832627b4f6" ("inline" ("filename" "message.txt")) ("en-US" "en-GB") "https://example.com/message.txt"))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "text/plain",
                   encoding: "QUOTED-PRINTABLE",
                   params: %{"charset" => "utf-8", "format" => "flowed", "name" => "message.txt"},
                   id: "<content-id@example.com>",
                   description: "Main body text",
                   octets: 4096,
                   lines: 200
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) application/pdf with all extension fields" do
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ("application" "pdf" ("name" "report.pdf") NIL "Quarterly Report" "base64" 1048576 "5d41402abc4b2a76b9719d911017c592" ("attachment" ("filename" "report.pdf" "creation-date" "Wed, 01 Jan 2025 00:00:00 GMT" "modification-date" "Fri, 10 Jan 2025 12:00:00 GMT" "size" "1048576")) "en" "https://example.com/reports/q1-2025.pdf"))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:onepart,
                 %{
                   mime_type: "application/pdf",
                   encoding: "BASE64",
                   params: %{"name" => "report.pdf"},
                   description: "Quarterly Report",
                   octets: 1_048_576
                 }}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) multipart with all extension fields on parts" do
    # Multipart with two parts, each having full extension data
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 100 5 "abc123" ("inline" NIL) "en" "https://example.com/plain.txt")("text" "html" ("charset" "utf-8") NIL NIL "quoted-printable" 500 25 "def456" ("inline" NIL) "en" "https://example.com/body.html") "alternative" ("boundary" "----=_Part_123") NIL NIL NIL))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:multipart,
                 [
                   {:onepart,
                    %{
                      mime_type: "text/plain",
                      encoding: "7BIT",
                      params: %{"charset" => "utf-8"},
                      octets: 100,
                      lines: 5
                    }},
                   {:onepart,
                    %{
                      mime_type: "text/html",
                      encoding: "QUOTED-PRINTABLE",
                      params: %{"charset" => "utf-8"},
                      octets: 500,
                      lines: 25
                    }}
                 ]}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) multipart with extension fields on multipart itself" do
    # Multipart/mixed with disposition, language, and location on the multipart container
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 256 12 NIL NIL NIL NIL)("application" "pdf" ("name" "doc.pdf") NIL NIL "base64" 50000 NIL ("attachment" ("filename" "doc.pdf")) NIL NIL) "mixed" ("boundary" "----=_NextPart_000") ("inline" NIL) ("en" "de") "https://example.com/email-content"))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:multipart,
                 [
                   {:onepart,
                    %{
                      mime_type: "text/plain",
                      encoding: "7BIT",
                      params: %{"charset" => "utf-8"},
                      octets: 256,
                      lines: 12
                    }},
                   {:onepart,
                    %{
                      mime_type: "application/pdf",
                      encoding: "BASE64",
                      params: %{"name" => "doc.pdf"},
                      octets: 50000
                    }}
                 ]}}
           ] = result
  end

  test "parse FETCH (BODYSTRUCTURE) nested multipart with extension fields" do
    # multipart/mixed containing multipart/alternative and an attachment
    result =
      Parser.parse_response(
        ~S|* 1 FETCH (BODYSTRUCTURE ((("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 100 5 "hash1" NIL "en" NIL)("text" "html" ("charset" "utf-8") NIL NIL "quoted-printable" 300 15 "hash2" NIL "en" NIL) "alternative" ("boundary" "alt-boundary") NIL "en" NIL)("image" "jpeg" ("name" "photo.jpg") "<img1@example.com>" "Vacation Photo" "base64" 250000 "hash3" ("attachment" ("filename" "photo.jpg")) NIL "https://example.com/photo.jpg") "mixed" ("boundary" "mixed-boundary") NIL ("en" "es") "https://example.com/email"))|
      )

    assert [
             fetch:
               {1, :body_structure,
                {:multipart,
                 [
                   {:multipart,
                    [
                      {:onepart,
                       %{
                         mime_type: "text/plain",
                         encoding: "7BIT",
                         params: %{"charset" => "utf-8"},
                         octets: 100,
                         lines: 5
                       }},
                      {:onepart,
                       %{
                         mime_type: "text/html",
                         encoding: "QUOTED-PRINTABLE",
                         params: %{"charset" => "utf-8"},
                         octets: 300,
                         lines: 15
                       }}
                    ]},
                   {:onepart,
                    %{
                      mime_type: "image/jpeg",
                      encoding: "BASE64",
                      params: %{"name" => "photo.jpg"},
                      id: "<img1@example.com>",
                      description: "Vacation Photo",
                      octets: 250_000
                    }}
                 ]}}
           ] = result
  end

  test "parse COPYUID response" do
    [
      copyuid: %{
        validity: 38_675_294,
        source_uids: [4, 5, 6, 7, 9, 12],
        destination_uids: [304, 305, 306, 307, 309, 312]
      }
    ] =
      Parser.parse_response("* OK [COPYUID 38675294 4:7,9,12 304:307,309,312] Copy completed\r\n")

    [copyuid: %{validity: 123_456, source_uids: [1], destination_uids: [2001]}] =
      Parser.parse_response("* OK [COPYUID 123456 1 2001] Copy completed\r\n")

    result = Parser.parse_response("* OK [COPYUID 987654 1:1000 2001:3000] Copy completed\r\n")

    assert [
             copyuid: %{
               validity: 987_654,
               source_uids: source_uids,
               destination_uids: destination_uids
             }
           ] = result

    assert length(source_uids) == 1000
    assert length(destination_uids) == 1000
    assert Enum.at(source_uids, 0) == 1
    assert Enum.at(source_uids, -1) == 1000
    assert Enum.at(destination_uids, 0) == 2001
    assert Enum.at(destination_uids, -1) == 3000
  end

  test "parse LIST response" do
    [list: %{flags: [:Noselect], delimiter: "/", name: "Public Folders"}] =
      Parser.parse_response("* LIST (\Noselect) \"/\" \"Public Folders\"\r\n")

    [list: %{flags: [:Unmarked, :HasNoChildren], delimiter: "/", name: "INBOX"}] =
      Parser.parse_response("* LIST (\Unmarked \HasNoChildren) \"/\" \"INBOX\"\r\n")

    [list: %{flags: [:Unmarked, :HasNoChildren], delimiter: "/", name: "Drafts"}] =
      Parser.parse_response("* LIST (\Unmarked \HasNoChildren) \"/\" \"Drafts\"\r\n")
  end

  test "parse FETCH response message/rfc822 forwarded email" do
    # The issue occurs when parsing a multipart message with message/rfc822 parts

    fetch_response =
      ~S|* 1 FETCH (BODY (("message" "rfc822" NIL NIL NIL "7bit" 16637 ("Thu, 31 Jul 2025 00:00:00 +0000" "SUBJECT" (("Name" NIL "user" "domain.org")) (("Name" NIL "user" "domain.org")) (("Name" NIL "user" "domain.org")) ((NIL NIL "name" "domain.org")) NIL "<67faa4d5-603e-46f8-b25e-877f2e61b173@domain.org>" "<name@domain.org>") (("text" "plain" ("charset" "UTF-8" "format" "flowed") NIL NIL "quoted-printable" 4791 128)("text" "html" ("charset" "UTF-8") NIL NIL "quoted-printable" 7681 173) "alternative") 379) "report"))|

    result = Parser.parse_response(fetch_response)

    # Should not crash and should return a fetch action with multipart body
    assert [fetch: {1, :body, {:multipart, _parts}}] = result
  end
end

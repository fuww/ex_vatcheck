defmodule ExVatcheck.VIESClientTest do
  use ExUnit.Case

  alias ExVatcheck.VIESClient
  alias Fixtures.VIESResponses

  import Mimic

  describe "new/0" do
    setup :verify_on_exit!

    test "creates a new VIES client" do
      stub(HTTPoison, :get, fn _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.valid_wsdl()}}
      end)

      assert VIESClient.new() == {:ok, %VIESClient{url: VIESResponses.service_url()}}
    end

    test "errors on VIES timeout" do
      stub(HTTPoison, :get, fn _ ->
        {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
      end)

      assert VIESClient.new() == {:error, "Service timed out"}
    end

    test "error when invalid WSDL XML returned" do
      stub(HTTPoison, :get, fn _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.invalid_wsdl()}}
      end)

      assert VIESClient.new() == {:error, "Unknown error: invalid_wsdl"}
    end

    test "errors on HTTPoison error" do
      stub(HTTPoison, :get, fn _ ->
        {:error, %HTTPoison.Error{id: nil, reason: :unexpected_error}}
      end)

      assert VIESClient.new() == {:error, "Unknown error: unexpected_error"}
    end
  end

  describe "check_vat/3" do
    setup :verify_on_exit!

    test "requests checkVatApprox on behalf of the configured requester" do
      client = %VIESClient{url: VIESResponses.service_url()}
      Application.put_env(:ex_vatcheck, :requester_vat_number, "NL123456789B01")
      on_exit(fn -> Application.delete_env(:ex_vatcheck, :requester_vat_number) end)

      expect(HTTPoison, :post, fn _, body, _ ->
        assert body =~ "<ns1:checkVatApprox>"
        assert body =~ "<ns1:requesterCountryCode>NL</ns1:requesterCountryCode>"
        assert body =~ "<ns1:requesterVatNumber>123456789B01</ns1:requesterVatNumber>"
        {:ok, %HTTPoison.Response{body: VIESResponses.valid_vat_approx_response()}}
      end)

      VIESClient.check_vat(client, "GB", "333289454")
    end

    test "uses checkVat and omits the requester when none is configured" do
      client = %VIESClient{url: VIESResponses.service_url()}

      expect(HTTPoison, :post, fn _, body, _ ->
        assert body =~ "<ns1:checkVat>"
        refute body =~ "checkVatApprox"
        refute body =~ "requester"
        {:ok, %HTTPoison.Response{body: VIESResponses.valid_vat_response()}}
      end)

      VIESClient.check_vat(client, "GB", "333289454")
    end

    test "correctly verifies a valid VAT identification number" do
      client = %VIESClient{url: VIESResponses.service_url()}

      expected = %{
        country_code: "GB",
        vat_number: "333289454",
        request_date: "2016-01-16",
        valid: true,
        name: "BRITISH BROADCASTING CORPORATION",
        address: "BC0 B1 D1 BROADCAST CENTRE\nWHITE CITY PLACE\n201 WOOD LANE\nLONDON\n\nW12 7TP"
      }

      stub(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.valid_vat_response()}}
      end)

      assert VIESClient.check_vat(client, "GB", "333289454") == {:ok, expected}
    end

    test "correctly marks an invalid VAT identification number" do
      client = %VIESClient{url: VIESResponses.service_url()}

      expected = %{
        country_code: "GB",
        vat_number: nil,
        request_date: "2016-01-16",
        valid: false,
        name: "---",
        address: "---"
      }

      stub(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.invalid_vat_response()}}
      end)

      assert VIESClient.check_vat(client, "GB", "123123123") == {:ok, expected}
    end

    test "returns the consultation number when a requester is configured" do
      client = %VIESClient{url: VIESResponses.service_url()}
      Application.put_env(:ex_vatcheck, :requester_vat_number, "NL123456789B01")
      on_exit(fn -> Application.delete_env(:ex_vatcheck, :requester_vat_number) end)

      expected = %{
        country_code: "GB",
        vat_number: "333289454",
        request_date: "2016-01-16",
        valid: true,
        name: "BRITISH BROADCASTING CORPORATION",
        address: "BC0 B1 D1 BROADCAST CENTRE\nWHITE CITY PLACE\n201 WOOD LANE\nLONDON\n\nW12 7TP",
        request_identifier: "WAPIAAAAaEhFZlcT"
      }

      stub(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.valid_vat_approx_response()}}
      end)

      assert VIESClient.check_vat(client, "GB", "333289454") == {:ok, expected}
    end

    test "handles invalid VAT response if ExVatcheck validation misses it" do
      client = %VIESClient{url: VIESResponses.service_url()}

      stub(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.invalid_input_fault_response()}}
      end)

      assert VIESClient.check_vat(client, "ZZ", "123") == {:error, "Unknown error: INVALID_INPUT"}
    end

    test "gracefully handles error due to unavailable VIES service" do
      client = %VIESClient{url: VIESResponses.service_url()}

      stub(HTTPoison, :post, fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: VIESResponses.service_unavailable_response()}}
      end)

      assert VIESClient.check_vat(client, "GB", "123123123") == {:error, "Service unavailable"}
    end

    test "gracefully handles VIES service timeouts" do
      client = %VIESClient{url: VIESResponses.service_url()}

      stub(HTTPoison, :post, fn _, _, _ ->
        {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
      end)

      assert VIESClient.check_vat(client, "GB", "123123123") == {:error, "Service timed out"}
    end
  end
end

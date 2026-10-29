-- | Ce profiluri deține portofelul, citite din activele lui.
-- |
-- | Partea pură a singurei întrebări pe care un portofel conectat o poate pune de unul singur. Tot
-- | ce se verifică aici e FILTRUL: ce se păstrează din balanță și ce nu, fiindcă un token greșit
-- | trimis la `/profiles/by-user-token/` primește 400, iar unul lipsă înseamnă că omul lipește iar
-- | un identificator de șaizeci de caractere.
module Test.Capabilities.WalletAssetsSpec (spec) where

import Prelude

import Capabilities.Wallet.Assets (userTokenAssetClasses, userTokenLabel)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | Politica registrului, măsurată pe preprod (`/status.attestation.policy_id`).
policy :: String
policy = "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"

-- | Forma pe care o produce `Value.to_json` din CSL. Numele sunt hex, iar cele patru etichete
-- | CIP-67 din față sunt singurul lucru care deosebește jumătățile unui profil de restul.
balance :: String
balance =
  """
{ "coin": "9842190"
, "multiasset":
    { "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3":
        { "000de140aaaa": "1"
        , "000643b0aaaa": "1"
        , "000de140bbbb": "1"
        , "00001070cccc": "1"
        , "000020e0dddd": "1"
        }
    , "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":
        { "000de140eeee": "1" }
    }
}
"""

spec :: Spec Unit
spec = do
  describe "the profiles a wallet holds" do
    it "keeps the user half and nothing else" do
      -- `000de140` e jumătatea de UTILIZATOR, cea care ajunge în portofel. `000643b0` e referința,
      -- care stă la validator cu datumul — un portofel n-ar trebui s-o aibă, dar dacă o are, nu e
      -- un profil al lui de trimis la ruta aceea. `00001070` și `000020e0` sunt etichetele de uz
      -- privat ale atestărilor și disputelor: tokenuri ale aceleiași politici, și niciunul profil.
      userTokenAssetClasses policy balance
        `shouldEqual`
          [ policy <> ".000de140aaaa"
          , policy <> ".000de140bbbb"
          ]

    it "ignores another policy's user tokens" do
      -- Aceeași etichetă CIP-67 sub altă politică e tokenul altui registru. Serverul n-ar găsi
      -- nimic pentru el, iar o cerere pe degeaba e tot o cerere.
      userTokenAssetClasses "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" balance
        `shouldEqual` [ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.000de140eeee" ]

    it "says nothing for a wallet that holds only ADA" do
      -- `multiasset` LIPSEȘTE cu totul atunci, nu e un obiect gol — cazul obișnuit al unui portofel
      -- nou, și singurul în care un decodor strict ar fi aruncat.
      userTokenAssetClasses policy """{ "coin": "2000000" }""" `shouldEqual` []

    it "says nothing instead of throwing on something that is not a balance" do
      userTokenAssetClasses policy "not json at all" `shouldEqual` []
      userTokenAssetClasses policy "" `shouldEqual` []

    it "sorts, because the order of JSON keys is not a contract" do
      -- Un ecran care își schimbă ordinea listei la fiecare citire arată rupt, iar ordinea cheilor
      -- unui obiect JSON nu e garantată de nimic.
      userTokenAssetClasses policy
        """{ "multiasset": { "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3": { "000de140ff": "1", "000de14011": "1" } } }"""
        `shouldEqual`
          [ policy <> ".000de14011"
          , policy <> ".000de140ff"
          ]

    it "names the label it filters on, so the test and the code cannot drift apart" do
      userTokenLabel `shouldEqual` "000de140"

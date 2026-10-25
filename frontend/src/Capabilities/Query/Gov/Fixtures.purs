-- | Fixturile de citire, separate de `Mock.purs` ca acela să rămână doar cablaj.
-- |
-- | __Fiecare e un payload măsurat, nu inventat.__ Se obține interogând serviciul care rulează și se
-- | lipește aici neatins. Unde un array real e lung (top 10 DRep-i, 5 acțiuni care se închid), se
-- | păstrează primele câteva elemente — e tot date reale, doar mai puține rânduri. Ce __nu__ se
-- | taie: `participation_by_epoch` (20 de puncte, cât cere graficul) și cele două desfășurări de
-- | acțiuni, pentru că numărul lor de categorii e el însuși un fapt de verificat.
module Capabilities.Query.Gov.Fixtures
  ( statusFixture
  , dashboardFixture
  , drepExplorerFixture
  ) where

-- | `GET /status` pe preprod, 2026-10-24. `epoch_params` e omis: niciun decodor nu-l citește încă,
-- | iar ecranul de Metodologie își va aduce propriul DTO.
statusFixture :: String
statusFixture =
  """
  { "network": "preprod"
  , "governance":
      { "epoch": 321
      , "slot": 137140009
      , "block_time": "2026-10-24T06:26:49Z"
      , "lag_seconds": 43
      , "is_ready": true
      , "source": "cardano-db-sync"
      }
  , "attest_lag_seconds": 0
  , "attestation":
      { "slot": 137140009
      , "kupo_tip_slot": 137140009
      , "lag_seconds": 0
      , "state": "following"
      , "last_sync_at": "2026-10-24T06:27:22.960784Z"
      , "is_ready": true
      , "policy_id": "648c6a732aa55efec29815bdd25cf65c565cf92619aadde1d31496d3"
      , "last_error": null
      , "source": "attest-sync/kupo"
      }
  , "drep_distr_epoch": 321
  , "amber_lag_seconds": 120
  , "ready_max_lag_seconds": 300
  , "metrics_as_of_epoch": 321
  }
  """

-- | `GET /pages/dashboard` pe preprod, 2026-10-25, cu parametrii impliciți (`top_limit` 10,
-- | `closing_soon_limit` 5, `epochs` 20).
-- |
-- | Două cifre din el merită citite împreună: `total_dreps` 294 și `active_dreps` 17 +
-- | `inactive_dreps` 187 = 204. Diferența de 90 sunt DRep-ii cu status `unknown`. De aceea linkul
-- | de pe dashboard spre listă poartă explicit `status=active&status=inactive`: altfel utilizatorul
-- | dă clic pe „204" și aterizează pe o listă de 294.
dashboardFixture :: String
dashboardFixture =
  """
  {
    "epoch": 321,
    "total_dreps": 294,
    "active_dreps": 17,
    "inactive_dreps": 187,
    "unknown_dreps": 90,
    "retired_dreps": 526,
    "power_epoch": 321,
    "drep_power_lovelace": 505754377083269,
    "always_abstain_lovelace": 432909247919877,
    "always_no_confidence_lovelace": 330754812982,
    "total_actions": 131,
    "actions_in_flight": 7,
    "treasury_requested_lovelace": 656466092110010,
    "treasury_enacted_lovelace": 0,
    "actions_by_type": [
      [
        "hard_fork_initiation",
        4
      ],
      [
        "info_action",
        17
      ],
      [
        "new_committee",
        8
      ],
      [
        "new_constitution",
        2
      ],
      [
        "no_confidence",
        2
      ],
      [
        "parameter_change",
        16
      ],
      [
        "treasury_withdrawals",
        82
      ]
    ],
    "actions_by_state": [
      [
        "dropped",
        6
      ],
      [
        "enacted",
        11
      ],
      [
        "expired",
        107
      ],
      [
        "proposed",
        7
      ],
      [
        "ratified",
        0
      ]
    ],
    "participation_by_epoch": [
      {
        "epoch": 302,
        "dreps_with_power": 169,
        "dreps_voted": 35,
        "votes_cast": 35,
        "participation_rate": 0.20710059171597633
      },
      {
        "epoch": 303,
        "dreps_with_power": 171,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.0935672514619883
      },
      {
        "epoch": 304,
        "dreps_with_power": 171,
        "dreps_voted": 3,
        "votes_cast": 3,
        "participation_rate": 0.017543859649122806
      },
      {
        "epoch": 305,
        "dreps_with_power": 172,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.005813953488372093
      },
      {
        "epoch": 306,
        "dreps_with_power": 173,
        "dreps_voted": 31,
        "votes_cast": 32,
        "participation_rate": 0.1791907514450867
      },
      {
        "epoch": 307,
        "dreps_with_power": 176,
        "dreps_voted": 11,
        "votes_cast": 13,
        "participation_rate": 0.0625
      },
      {
        "epoch": 308,
        "dreps_with_power": 176,
        "dreps_voted": 40,
        "votes_cast": 40,
        "participation_rate": 0.22727272727272727
      },
      {
        "epoch": 309,
        "dreps_with_power": 176,
        "dreps_voted": 4,
        "votes_cast": 4,
        "participation_rate": 0.022727272727272728
      },
      {
        "epoch": 310,
        "dreps_with_power": 177,
        "dreps_voted": 15,
        "votes_cast": 17,
        "participation_rate": 0.0847457627118644
      },
      {
        "epoch": 311,
        "dreps_with_power": 177,
        "dreps_voted": 0,
        "votes_cast": 0,
        "participation_rate": 0.0
      },
      {
        "epoch": 312,
        "dreps_with_power": 178,
        "dreps_voted": 7,
        "votes_cast": 13,
        "participation_rate": 0.03932584269662921
      },
      {
        "epoch": 313,
        "dreps_with_power": 181,
        "dreps_voted": 17,
        "votes_cast": 31,
        "participation_rate": 0.09392265193370165
      },
      {
        "epoch": 314,
        "dreps_with_power": 181,
        "dreps_voted": 1,
        "votes_cast": 1,
        "participation_rate": 0.0055248618784530384
      },
      {
        "epoch": 315,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 316,
        "dreps_with_power": 182,
        "dreps_voted": 2,
        "votes_cast": 2,
        "participation_rate": 0.01098901098901099
      },
      {
        "epoch": 317,
        "dreps_with_power": 186,
        "dreps_voted": 17,
        "votes_cast": 18,
        "participation_rate": 0.0913978494623656
      },
      {
        "epoch": 318,
        "dreps_with_power": 187,
        "dreps_voted": 26,
        "votes_cast": 26,
        "participation_rate": 0.13903743315508021
      },
      {
        "epoch": 319,
        "dreps_with_power": 186,
        "dreps_voted": 24,
        "votes_cast": 24,
        "participation_rate": 0.12903225806451613
      },
      {
        "epoch": 320,
        "dreps_with_power": 185,
        "dreps_voted": 16,
        "votes_cast": 16,
        "participation_rate": 0.08648648648648649
      },
      {
        "epoch": 321,
        "dreps_with_power": 185,
        "dreps_voted": 9,
        "votes_cast": 9,
        "participation_rate": 0.04864864864864865
      }
    ],
    "top_dreps_by_power": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "closing_soon": [
      {
        "id": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e#0",
        "bech32": "gov_action1dxyudrcykazjcgk7ns9etaqfvrxp074h80prvh6363k6x8djca0qqpx4v94",
        "type": "no_confidence",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135501681,
          "epoch": 317,
          "time": "2026-10-05T07:21:21Z",
          "tx_hash": "6989c68f04b7452c22de9c0b95f40960cc17fab73bc2365f51d46da31db2c75e"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      },
      {
        "id": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0#0",
        "bech32": "gov_action1uhfg3dwws8ptqja63dwnmxnf4jdq0p2yqghapmqj87jhzlt0y0cqqauysd8",
        "type": "hard_fork_initiation",
        "title": null,
        "abstract": null,
        "anchor_status": "unreachable",
        "proposed_at": {
          "slot": 135504192,
          "epoch": 317,
          "time": "2026-10-05T08:03:12Z",
          "tx_hash": "e5d288b5ce81c2b04bba8b5d3d9a69ac9a078544022fd0ec123fa5717d6f23f0"
        },
        "expires_epoch": 324,
        "last_votable_epoch": 323,
        "lifecycle": {
          "state": "proposed",
          "ratified_epoch": null,
          "enacted_epoch": null,
          "expired_epoch": null,
          "dropped_epoch": null,
          "formula_id": "gov_action_state_v1"
        },
        "deposit": 1000000000,
        "return_address": "stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4",
        "treasury_amount": null,
        "votes_cast": 0
      }
    ]
  }
  """

-- | `GET /pages/drep-explorer?limit=4&order_by=voting_power&sort_order=desc` pe preprod,
-- | 2026-10-25.
-- |
-- | Trei fapte măsurate pe care ecranul trebuie să le respecte, și pe care fixtura le păstrează:
-- |
-- |   * `status_facets` însumează 820, iar `total` e 294. Facetele se numără fiecare cu propriul
-- |     predicat scos (semantică standard de facet), deci __nu se calculează procente din ele__;
-- |   * `anchor_facets` însumează 131: un DRep fără ancoră nu intră în nicio categorie;
-- |   * `power_buckets` __da__ însumează la 294, pentru că fiecare DRep cade în exact un bucket.
-- |     E singura desfășurare din care un procent are sens.
-- |
-- | `language_facets` are o cheie goală (`""`, 4 DRep-i): limba e un câmp liber din metadate, iar
-- | șirul gol e o valoare pe care o scrie cineva, nu absența valorii.
drepExplorerFixture :: String
drepExplorerFixture =
  """
  {
    "items": [
      {
        "id": "drep1ygzlzlzj8r9c3zutlgh9ugqx958cwr6q704xtt9j5uf4lzsz9rwhm",
        "hex": "05f17c5238cb888b8bfa2e5e20062d0f870f40f3ea65acb2a7135f8a",
        "has_script": false,
        "status": "active",
        "is_active": true,
        "active_until_epoch": 324,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2025-07-14T05:02:00Z",
        "age_days": 468,
        "voting_power": 400644627419166,
        "voting_power_epoch": 321,
        "delegator_count": 19,
        "eligible_actions": 105,
        "votes_cast": 10,
        "participation_rate": 0.09523809523809523,
        "rationale_rate": 0.0,
        "open_actions_unvoted": 7,
        "last_vote_at": "2026-07-29T19:21:51Z",
        "as_of_epoch": 321
      },
      {
        "id": "drep1yg3j4dkpz3j0eh4e9d5l3uy43sf5ndz2wv4c2fywgdcu4wsjmj5wp",
        "hex": "232ab6c11464fcdeb92b69f8f0958c1349b44a732b85248e4371caba",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 296,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": "unreachable",
        "registered_at": "2026-01-20T12:15:56Z",
        "age_days": 277,
        "voting_power": 60594158706858,
        "voting_power_epoch": 321,
        "delegator_count": 417,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1ygnl9fjlz3pahx5vd2m6y4ya0562n8ttqzss9ncacu6l6pqwm2php",
        "hex": "27f2a65f1443db9a8c6ab7a2549d7d34a99d6b00a102cf1dc735fd04",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 199,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2024-11-09T09:41:55Z",
        "age_days": 715,
        "voting_power": 7264462090316,
        "voting_power_epoch": 321,
        "delegator_count": 5,
        "eligible_actions": 119,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      },
      {
        "id": "drep1yfleuad6rwdgk5y640aa3d4jc3gdukyq5vcxc84lx8mlklcw50hva",
        "hex": "7f9e75ba1b9a8b509aabfbd8b6b2c450de5880a3306c1ebf31f7fb7f",
        "has_script": false,
        "status": "inactive",
        "is_active": false,
        "active_until_epoch": 297,
        "given_name": null,
        "image_url": null,
        "language": null,
        "anchor_status": null,
        "registered_at": "2026-03-18T10:32:09Z",
        "age_days": 221,
        "voting_power": 7009495872731,
        "voting_power_epoch": 321,
        "delegator_count": 1,
        "eligible_actions": 36,
        "votes_cast": 0,
        "participation_rate": 0.0,
        "rationale_rate": null,
        "open_actions_unvoted": 7,
        "last_vote_at": null,
        "as_of_epoch": 321
      }
    ],
    "total": 294,
    "limit": 4,
    "offset": 0,
    "epoch": 321,
    "status_facets": [
      [
        "active",
        17
      ],
      [
        "inactive",
        187
      ],
      [
        "retired",
        526
      ],
      [
        "unknown",
        90
      ]
    ],
    "anchor_facets": [
      [
        "unreachable",
        51
      ],
      [
        "valid",
        50
      ],
      [
        "hash_mismatch",
        26
      ],
      [
        "invalid_schema",
        4
      ]
    ],
    "language_facets": [
      [
        "en-us",
        50
      ],
      [
        "",
        4
      ]
    ],
    "power_buckets": [
      {
        "lo": 0,
        "hi": 1,
        "count": 109
      },
      {
        "lo": 1,
        "hi": 1000000000,
        "count": 28
      },
      {
        "lo": 1000000000,
        "hi": 10000000000,
        "count": 53
      },
      {
        "lo": 10000000000,
        "hi": 100000000000,
        "count": 69
      },
      {
        "lo": 100000000000,
        "hi": 1000000000000,
        "count": 23
      },
      {
        "lo": 1000000000000,
        "hi": null,
        "count": 12
      }
    ]
  }
  """

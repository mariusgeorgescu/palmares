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
  , drepDetailFixture
  , govActionListFixture
  , govActionDetailFixture
  , votesListFixture
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

-- | `GET /pages/drep/drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z` pe preprod,
-- | 2026-10-25. Ales dintre cei 294 pentru că e cazul __greu__: DRep script, cu ancoră validă, cu
-- | două referințe externe, cu voturi pe patru tipuri de acțiuni din șapte — adică exact ecranul pe
-- | care se vede dacă randarea unui document străin e făcută cu grijă.
-- |
-- | `power_by_epoch` e ultimele 20 de puncte din cele 94 reale. `top_delegators` sunt toți cinci,
-- | __inclusiv al cincilea, care are `lovelace: null`__: un delegator pentru care epoca nu are
-- | stake înregistrat (limitarea §8.3 din contractul API-ului). Fixtura de dinainte îi tăia, și
-- | exact de aceea a trecut testele și a căzut în browser pe serverul adevărat.
drepDetailFixture :: String
drepDetailFixture =
  """
  {
    "drep": {
      "id": "drep1ydmraa6kv8cvmry059v608tehl50nfmg0z764lmsqkvwurs40sw2z",
      "hex": "763ef75661f0cd8c8fa159a79d79bfe8f9a76878bdaaff700598ee0e",
      "has_script": true,
      "status": "inactive",
      "is_active": false,
      "active_until_epoch": 189,
      "given_name": "Logical Mechanism dRep",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "language": "en-us",
      "anchor_status": "valid",
      "registered_at": "2024-09-06T23:10:12Z",
      "age_days": 778,
      "voting_power": 5942176444940,
      "voting_power_epoch": 321,
      "delegator_count": 5,
      "eligible_actions": 120,
      "votes_cast": 1,
      "participation_rate": 0.008333333333333333,
      "rationale_rate": 0.0,
      "open_actions_unvoted": 7,
      "last_vote_at": "2024-09-06T23:22:48Z",
      "as_of_epoch": 321
    },
    "metrics": {
      "as_of_epoch": 321,
      "eligible_actions": 120,
      "votes_cast": 1,
      "open_actions_unvoted": 7,
      "participation_rate": 0.008333333333333333,
      "rationale_verified": 0,
      "rationale_inline": 0,
      "rationale_unverified": 0,
      "rationale_pending": 0,
      "rationale_absent": 1,
      "rationale_cip100_valid": 0,
      "rationale_rate": 0.0,
      "vote_latency_median_hours": 0.05444444444444444,
      "vote_latency_p90_hours": 0.05444444444444444,
      "vote_latency_sample": 1,
      "age_days": 778,
      "final_votes": {
        "yes": 1,
        "no": 0,
        "abstain": 0
      },
      "votes_by_type": [
        [
          "hard_fork_initiation",
          {
            "eligible_actions": 2,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "info_action",
          {
            "eligible_actions": 17,
            "votes_cast": 1,
            "yes": 1,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.058823529411764705
          }
        ],
        [
          "new_committee",
          {
            "eligible_actions": 7,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "new_constitution",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "no_confidence",
          {
            "eligible_actions": 1,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "parameter_change",
          {
            "eligible_actions": 11,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ],
        [
          "treasury_withdrawals",
          {
            "eligible_actions": 81,
            "votes_cast": 0,
            "yes": 0,
            "no": 0,
            "abstain": 0,
            "participation_rate": 0.0
          }
        ]
      ],
      "formula_ids": [
        "participation_rate_v1",
        "rationale_rate_v1",
        "age_days_v1",
        "delegator_retention_rate_v1",
        "vote_latency_median_hours_v1",
        "votes_by_type_v1"
      ]
    },
    "delegator_stats": {
      "delegator_count": 5,
      "delegator_count_prev": 5,
      "delegators_retained": 5,
      "delegators_joined": 0,
      "delegators_left": 0,
      "delegator_retention_rate": 1.0,
      "window_epochs": 10
    },
    "power_by_epoch": [
      {
        "epoch": 302,
        "lovelace": 5889967679740,
        "delegator_count": 5
      },
      {
        "epoch": 303,
        "lovelace": 5874056067112,
        "delegator_count": 5
      },
      {
        "epoch": 304,
        "lovelace": 5874836087448,
        "delegator_count": 5
      },
      {
        "epoch": 305,
        "lovelace": 5879754429475,
        "delegator_count": 5
      },
      {
        "epoch": 306,
        "lovelace": 5883923005781,
        "delegator_count": 5
      },
      {
        "epoch": 307,
        "lovelace": 5888569602056,
        "delegator_count": 5
      },
      {
        "epoch": 308,
        "lovelace": 5893190135192,
        "delegator_count": 5
      },
      {
        "epoch": 309,
        "lovelace": 5897720675965,
        "delegator_count": 5
      },
      {
        "epoch": 310,
        "lovelace": 5901872333057,
        "delegator_count": 5
      },
      {
        "epoch": 311,
        "lovelace": 5906522519873,
        "delegator_count": 5
      },
      {
        "epoch": 312,
        "lovelace": 5910755571684,
        "delegator_count": 5
      },
      {
        "epoch": 313,
        "lovelace": 5910762282359,
        "delegator_count": 5
      },
      {
        "epoch": 314,
        "lovelace": 5910770233192,
        "delegator_count": 5
      },
      {
        "epoch": 315,
        "lovelace": 5914902920642,
        "delegator_count": 5
      },
      {
        "epoch": 316,
        "lovelace": 5919918376352,
        "delegator_count": 5
      },
      {
        "epoch": 317,
        "lovelace": 5924415104092,
        "delegator_count": 5
      },
      {
        "epoch": 318,
        "lovelace": 5928925649832,
        "delegator_count": 5
      },
      {
        "epoch": 319,
        "lovelace": 5933433550288,
        "delegator_count": 5
      },
      {
        "epoch": 320,
        "lovelace": 5937875560062,
        "delegator_count": 5
      },
      {
        "epoch": 321,
        "lovelace": 5942176444940,
        "delegator_count": 5
      }
    ],
    "top_delegators": [
      {
        "stake_address": "stake_test1uzrvw62pn24xw0yk8ksyuj6m4ezg6jgw9n4vjqktstjd5aspv59nv",
        "lovelace": 5912487235860,
        "delegated_at": {
          "slot": 69983290,
          "epoch": 165,
          "time": "2024-09-06T23:48:10Z",
          "tx_hash": "7215b4e94e30d1341b1c30f9defacfa9a583a2ef0973dcd3e2b862d9f5e386da"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1ur7sufjy8lfactkprnwl5x7mjn0ugajqg920n6uv4g7l68cra6p74",
        "lovelace": 11647105014,
        "delegated_at": {
          "slot": 71680542,
          "epoch": 169,
          "time": "2024-09-26T15:15:42Z",
          "tx_hash": "2d91ed34e62bcca5b1e80673044aec56ce2da17794be843a96e8784fcc97ca1a"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzl65wzu364hh0wxex94qsf5xkeaq2mnmc7xgnsnsjuqr4qruvxwu",
        "lovelace": 8863539868,
        "delegated_at": {
          "slot": 69981608,
          "epoch": 165,
          "time": "2024-09-06T23:20:08Z",
          "tx_hash": "46bd643c23eabbce70deebbf23127022f109f7813086b123b4cedca8f3d95983"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1upqt8jvd8d045a6gs2wkzt57rnx47s5ewz4un2l746r847g7hgw24",
        "lovelace": 180912096,
        "delegated_at": {
          "slot": 69981238,
          "epoch": 165,
          "time": "2024-09-06T23:13:58Z",
          "tx_hash": "fdd0e44251da1b0b6b6c9d8e92ad0010d3e13640f608ccf91c18278b9ab99861"
        },
        "is_current": true
      },
      {
        "stake_address": "stake_test1uzyp0n0lqk65g9wae0uhn3fdzevww4u7w665w46wsdmeaysjvtvpu",
        "lovelace": null,
        "delegated_at": {
          "slot": 88520092,
          "epoch": 208,
          "time": "2025-04-09T12:54:52Z",
          "tx_hash": "bcfd8c71d322df7205013b0a5f5f418f80b733f95c37b31109557bfc3022317a"
        },
        "is_current": true
      }
    ],
    "updates": [
      {
        "kind": "updated",
        "at": {
          "slot": 69981800,
          "epoch": 165,
          "time": "2024-09-06T23:23:20Z",
          "tx_hash": "ebab27b88379f662d5bdcd2db7c0be391fd94674a889255411d540b6684e5c13"
        },
        "deposit": null,
        "anchor_url": "https://www.logicalmechanism.io/drepTestnet",
        "anchor_status": "valid"
      },
      {
        "kind": "registered",
        "at": {
          "slot": 69981012,
          "epoch": 165,
          "time": "2024-09-06T23:10:12Z",
          "tx_hash": "744fb092ab6d8a4d8ca8f66ea3c0abb6b9d49381205aa41c75c8597e91137948"
        },
        "deposit": 500000000,
        "anchor_url": null,
        "anchor_status": null
      }
    ],
    "anchor_content": {
      "given_name": "Logical Mechanism dRep",
      "objectives": "We want to provide expert consulting, comprehensive knowledge, and in-depth research into the future of Cardano.",
      "motivations": "We are a technical consulting company specializing in open-sourced decentralized applications for the everyday user. We know Cardano inwards and out.",
      "qualifications": "We are Plutus pioneers, dApp developers, stake pool operators, and open-source contributors. We know Cardano.",
      "image_url": "https://www.logicalmechanism.io/img/fullLogo.png",
      "payment_address": "addr_test1qrvnxkaylr4upwxfxctpxpcumj0fl6fdujdc72j8sgpraa9l4gu9er4t0w7udjvt2pqngddn6q4h8h3uv38p8p9cq82qav4lmp",
      "references": [
        {
          "label": "The Logical Mechanism Website",
          "uri": "https://www.logicalmechanism.io/"
        },
        {
          "label": "The Logical Mechanism GitHub",
          "uri": "https://github.com/logical-mechanism"
        }
      ]
    }
  }
  """

-- | `GET /gov-actions?limit=4&order_by=proposed_at&sort_order=desc` pe preprod, 2026-10-25.
govActionListFixture :: String
govActionListFixture =
  """
  {"items":[{"id":"04f23439388432a22b6830425d0a8114a168ac5ead2767fe122eb956e8593f44#0","bech32":"gov_action1qnergwfcsse2y2mgxpp96z5pzjsk3tz745nk0lsj96u4d6ze8azqqdc2a6v","type":"parameter_change","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":136473457,"epoch":319,"time":"2026-10-16T13:17:37Z","tx_hash":"04f23439388432a22b6830425d0a8114a168ac5ead2767fe122eb956e8593f44"},"expires_epoch":326,"last_votable_epoch":325,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":43},{"id":"7277c327fafdfc877e6e6414016c04b04280ffb492518cfcc00a7fdcd19b6e5a#0","bech32":"gov_action1wfmuxfl6lh7gwlnwvs2qzmqykppgpla5jfgcelxqpflae5vmdedqqswtv74","type":"parameter_change","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135811038,"epoch":318,"time":"2026-10-08T21:17:18Z","tx_hash":"7277c327fafdfc877e6e6414016c04b04280ffb492518cfcc00a7fdcd19b6e5a"},"expires_epoch":325,"last_votable_epoch":324,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":2},{"id":"466c87a7002a39fadb8d6eb0d27c94e71a5f363cf9152cc7d8ca01315d82f458#0","bech32":"gov_action1gekg0fcq9gul4kudd6cdyly5uud97d3uly2je37cegqnzhvz73vqqp5s9yg","type":"treasury_withdrawals","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135688800,"epoch":317,"time":"2026-10-07T11:20:00Z","tx_hash":"466c87a7002a39fadb8d6eb0d27c94e71a5f363cf9152cc7d8ca01315d82f458"},"expires_epoch":324,"last_votable_epoch":323,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":42000000,"votes_cast":1},{"id":"28dc44f2e6bdd8ca52cf14aebf935fe8dd4690ed65b7937170ab16718cca94e5#0","bech32":"gov_action19rwyfuhxhhvv55k0zjhtly6larw5dy8dvkmexuts4vt8rrx2jnjsq3c2j2m","type":"new_committee","title":null,"abstract":null,"anchor_status":"unreachable","proposed_at":{"slot":135506963,"epoch":317,"time":"2026-10-05T08:49:23Z","tx_hash":"28dc44f2e6bdd8ca52cf14aebf935fe8dd4690ed65b7937170ab16718cca94e5"},"expires_epoch":324,"last_votable_epoch":323,"lifecycle":{"state":"proposed","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":null,"dropped_epoch":null,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uzrr46pd4wn2qpzvv5fpdeycndzsgjc899jn8e4rmten3ngcgm3f4","treasury_amount":null,"votes_cast":1}],"total":131,"limit":4,"offset":0,"next_cursor":null}  """

-- | `GET /pages/gov-action/90de87d4…%230` pe preprod, 2026-10-25 — o retragere de trezorerie de un
-- | milion de ADA, cu document CIP-108 valid.
-- |
-- | Trei fapte din el pe care ecranul trebuie să le spună cinstit:
-- |
-- |   * `ratio` e `null` deși s-au exprimat voturi — pragul se calculează pe putere, iar puterea de
-- |     ambele părți era zero. „0%" ar fi o afirmație despre rezultat;
-- |   * ciclul de viață are __și__ `expired_epoch` 304 __și__ `dropped_epoch` 305;
-- |   * `references` conține același link de două ori, iar `rationale` are peste 2.500 de
-- |     caractere. Amândouă se randează așa cum sunt: e documentul lor.
govActionDetailFixture :: String
govActionDetailFixture =
  """
  {"action":{"id":"90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392#0","bech32":"gov_action1jr0g04rwvdz3rrqpm30vwqd5mnjky8l68v0e3g74t6e5apw6wwfqq37hpcl","type":"treasury_withdrawals","title":"Rename the Chang 2 Hard Fork to the Plomin Hard Fork","abstract":"The Intersect Hard Fork Working Group proposes to name the next Cardano hard fork the “Plomin Hard Fork” in memory of Cardano community contributor Matthew Plomin.","anchor_status":"valid","proposed_at":{"slot":127034777,"epoch":297,"time":"2026-06-29T07:26:17Z","tx_hash":"90de87d46e6345118c01dc5ec701b4dce5621ffa3b1f98a3d55eb34e85da7392"},"expires_epoch":304,"last_votable_epoch":303,"lifecycle":{"state":"expired","ratified_epoch":null,"enacted_epoch":null,"expired_epoch":304,"dropped_epoch":305,"formula_id":"gov_action_state_v1"},"deposit":1000000000,"return_address":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","treasury_amount":1000000000000,"votes_cast":58},"tallies":[{"role":"drep","epoch":304,"yes_power":0,"no_power":1095127719870,"abstain_power":0,"yes_count":7,"no_count":2,"abstain_count":49,"ratio":0.0,"threshold":0.67,"threshold_param":"dvt_treasury_withdrawal","basis":"cast_votes_only","formula_id":"tally_cast_votes_v1"}],"withdrawals":[{"beneficiary":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","amount":1000000000000,"enacted_at":null,"paid_heuristic":false}],"param_changes":[],"proposer":{"stake_address":"stake_test1uppy2gm2hqzkwc80em4mlat73j4jyqvzhclrvsu72g9xg4q2yweet","actions_count":2},"anchor_content":{"title":"Rename the Chang 2 Hard Fork to the Plomin Hard Fork","abstract":"The Intersect Hard Fork Working Group proposes to name the next Cardano hard fork the “Plomin Hard Fork” in memory of Cardano community contributor Matthew Plomin.","motivation":"There is a tradition of naming hard forks in memory of notable historical figures or significant contributors to the Cardano community. Naming this hard fork in memory of Matthew Plomin would memorialize his actions in life to selflessly support and contribute to the Cardano blockchain ecosystem.","rationale":"Renaming the “Second Chang Hard Fork” (Chang 2) to the Plomin Hard Fork, in memory of Cardano community contributor Matthew Plomin, reflects a natural progression of Cardano’s governance growth. Phil Chang was an employee of Input Output who made significant contributions to Cardano’s governance system to help transfer control and responsibility of the blockchain into the hands of the community. Matthew Plomin was an exemplar of the Cardano community, representing every individual who stands ready to pick up the torch and carry the ecosystem forward.\n\nMatthew was a much loved and respected member of the Cardano community. He passed unexpectedly on November 14th, 2024. Originally hailing from Indiana, USA; he earned a Bachelor of Science in Management degree from Purdue University where he met and married the love of his life, Jillian (Shaw). He went on to receive his Master of Business Administration Degree from George Washington University before joining the DWS Group (Deutsche Bank) and rising to the Head of the US Money Market Credit Research team. His expertise in the traditional finance world was instrumental in his journey to found $USDM, a Cardano-native stable coin pegged to the US Dollar and fully backed by dollar reserves.\n\nAs a Cardano community member, Matthew was always eager to learn more and excited to help others work through issues they encountered with their projects in the ecosystem. He taught himself how to mint native assets, experimenting with social games and helping Jillian to publish a book she authored in a serialized, token-based format. Seeing the need for a US Dollar-backed Stablecoin on Cardano, Matthew assembled a team that would become the Moneta project. Despite limited institutional backing during a market bottom, the community stepped up to champion him and their support helped his dream become a reality.\n\nMatthew leaves behind his wife, Jillian, their seven children, and the Moneta team. His legacy lives on through the work that he accomplished and the inspiration that he kindled in others. As a devout Roman Catholic Christian, Matthew lived out the “Golden Rule” to “do unto others as you would have them do unto you,” and the world is a better place for him being in it.","references":[{"label":"Vasil Hard Fork | Cardano Docs","uri":"https://docs.cardano.org/about-cardano/evolution/upgrades/vasil/"},{"label":"Chang upgrade #1 hard fork achieved! | Intersect MBO","uri":"https://www.intersectmbo.org/news/chang-upgrade-1-hard-fork-achieved"},{"label":"Vasil Hard Fork | Cardano Docs","uri":"https://docs.cardano.org/about-cardano/evolution/upgrades/vasil/"},{"label":"Chang upgrade #1 hard fork achieved! | Intersect MBO","uri":"https://www.intersectmbo.org/news/chang-upgrade-1-hard-fork-achieved"}]}}  """

-- | `GET /votes?limit=4&anchor_status=valid&order_by=cast_at&sort_order=desc` pe preprod,
-- | 2026-10-25.
-- |
-- | Filtrul pe ancoră validă e deliberat: din ~934 de voturi finale, __opt__ au un raționament
-- | verificat, iar fixtura trebuie să conțină cazul care se randează greu. Primul rând are
-- | `is_final: false` și `revote_count: 3` — un vot care a fost înlocuit, exact rândul pe care un
-- | ecran neatent l-ar număra ca încă unul.
votesListFixture :: String
votesListFixture =
  """
  {
    "items": [
      {
        "gov_action_id": "78a9aafe2e4e14828efa8cd5202fec08c996a9a00c7d56b317b6a95a80510db3#0",
        "gov_action_bech32": "gov_action10z564l3wfc2g9rh63n2jqtlvpryed2dqp374dvchk6544qz3pkesq7cqrfs",
        "gov_action_type": "parameter_change",
        "gov_action_title": null,
        "voter_role": "drep",
        "voter_id": "drep1y0lpypv3vgrg6scz4emwl5u9z5aq3m5z4m2x5zn0gguvu6sv8yks9",
        "voter_hot_hash": "fe12059162068d4302ae76efd385153a08ee82aed46a0a6f4238ce6a",
        "voter_name": null,
        "verdict": "yes",
        "cast_at": {
          "slot": 130847265,
          "epoch": 306,
          "time": "2026-08-12T10:27:45Z",
          "tx_hash": "952df62401da2dac25179da0ab55e0088bc164e37bdd13f5c2312e6229a26864"
        },
        "latency_hours": 112.63222222222223,
        "is_final": false,
        "is_first": true,
        "revote_count": 3,
        "anchor": {
          "url": "https://gateway.pinata.cloud/ipfs/bafkreigd4cspq46cuvm2vue4vlguldgpmkc572aykn56mghd23z2lgo6sm",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "97d5bcc30ce59be99bd808345d99be8c18aa474abb2e5dcd9183b44f976ce12d#0",
        "gov_action_bech32": "gov_action1jl2mescvukd7nx7cpq69mxd73sv25362hvh9mnv3sw6yl9mvuyksqxdcx6k",
        "gov_action_type": "treasury_withdrawals",
        "gov_action_title": null,
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdgf3h7sm6a8yhad66fpnr7r8m54n7l8umklrddxjhsxucgkudvrr",
        "voter_hot_hash": "e3a4c41d67592a1b8d87c62e5c5d73f7e8db836171945412d13f40f8",
        "voter_name": null,
        "verdict": "no",
        "cast_at": {
          "slot": 79926192,
          "epoch": 188,
          "time": "2024-12-31T01:43:12Z",
          "tx_hash": "41bcea0a3c79ca41fb4c3990f7bf060aec5786dba2dbe340d9f13673c9bf66fd"
        },
        "latency_hours": 346.5725,
        "is_final": true,
        "is_first": false,
        "revote_count": 2,
        "anchor": {
          "url": "https://hornan7.github.io/mike_hornan.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "acc84cdb5eae8fe33793a9329bdd73b51eef7d9a33f25352783015aaa63c16fe#0",
        "gov_action_bech32": "gov_action14nyyek674687xdun4yefhhtnk50w7lv6x0e9x5ncxq264f3uzmlqqn60xhh",
        "gov_action_type": "treasury_withdrawals",
        "gov_action_title": null,
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdgf3h7sm6a8yhad66fpnr7r8m54n7l8umklrddxjhsxucgkudvrr",
        "voter_hot_hash": "e3a4c41d67592a1b8d87c62e5c5d73f7e8db836171945412d13f40f8",
        "voter_name": null,
        "verdict": "no",
        "cast_at": {
          "slot": 79926192,
          "epoch": 188,
          "time": "2024-12-31T01:43:12Z",
          "tx_hash": "41bcea0a3c79ca41fb4c3990f7bf060aec5786dba2dbe340d9f13673c9bf66fd"
        },
        "latency_hours": 346.56583333333333,
        "is_final": true,
        "is_first": false,
        "revote_count": 2,
        "anchor": {
          "url": "https://hornan7.github.io/mike_hornan.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      },
      {
        "gov_action_id": "b52f02288e3ce8c7e57455522f4edd09c12797749e2db32098ecbe980b645d45#0",
        "gov_action_bech32": "gov_action1k5hsy2yw8n5v0et524fz7nkap8qj09m5nckmxgycajlfszmyt4zsqp0n7ft",
        "gov_action_type": "parameter_change",
        "gov_action_title": "Plutus V3 Cost Model Parameter Changes Prior to Chang#2",
        "voter_role": "constitutional_committee",
        "voter_id": "cc_cold1zdd8rutlfnjvrs97q56ht4ch4hn2mzsa23faq2n9eeqdfvgss2fuc",
        "voter_hot_hash": "104f3db4e905fd008396f53a6d035e290f97f6172d3792673b213956",
        "voter_name": null,
        "verdict": "yes",
        "cast_at": {
          "slot": 75624648,
          "epoch": 178,
          "time": "2024-11-11T06:50:48Z",
          "tx_hash": "0b16cf9a6f3e6b1c9fbe66b7f828786e89d8ef9dda16d53bc5cf37a08cee7bd3"
        },
        "latency_hours": 133.57361111111112,
        "is_final": true,
        "is_first": true,
        "revote_count": 1,
        "anchor": {
          "url": "https://raw.githubusercontent.com/Eastern-Cardano-Council/icc-ga-rationales/refs/heads/main/preprod/ga05/ga05-rationale.jsonld",
          "status": "valid",
          "cip100_valid": true
        },
        "voting_power": null,
        "voting_power_epoch": null
      }
    ],
    "total": 8,
    "limit": 4,
    "offset": 0
  }
  """
